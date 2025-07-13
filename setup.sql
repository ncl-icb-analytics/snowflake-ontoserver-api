CREATE SCHEMA IF NOT EXISTS EXTERNAL_ACCESS.ONTOSERVER;

USE DATABASE EXTERNAL_ACCESS;
USE SCHEMA EXTERNAL_ACCESS.ONTOSERVER;

-- =====================================================
-- SECURE OBJECTS SECTION
-- These require ACCOUNTADMIN privileges
-- and must be created in EXTERNAL_ACCESS database
-- =====================================================

-- Create network rule
CREATE OR REPLACE NETWORK RULE EXTERNAL_ACCESS.ONTOSERVER.onto_api_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('ontology.onelondon.online');

-- Create OAuth security integration
-- This is a global object (not database-specific) but must be referenced correctly
CREATE OR REPLACE SECURITY INTEGRATION onto_oauth_integration
  TYPE = API_AUTHENTICATION
  AUTH_TYPE = OAUTH2
  OAUTH_CLIENT_AUTH_METHOD = CLIENT_SECRET_POST
  OAUTH_CLIENT_ID = 'redacted' -- Enter credentials
  OAUTH_CLIENT_SECRET = 'redacted' -- Enter credentials
  OAUTH_GRANT = 'CLIENT_CREDENTIALS'
  OAUTH_TOKEN_ENDPOINT = 'https://ontology.onelondon.online/authorisation/auth/realms/terminology/protocol/openid-connect/token'
  ENABLED = TRUE;

-- Create OAuth secret
CREATE OR REPLACE SECRET EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret
  TYPE = OAUTH2
  API_AUTHENTICATION = onto_oauth_integration;

-- Create External Access Integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION onto_api_integration
  ALLOWED_NETWORK_RULES = (EXTERNAL_ACCESS.ONTOSERVER.onto_api_rule)
  ALLOWED_API_AUTHENTICATION_INTEGRATIONS = (onto_oauth_integration)
  ALLOWED_AUTHENTICATION_SECRETS = (EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
  ENABLED = TRUE;

-- =====================================================
-- USER-FACING FUNCTIONS SECTION
-- =====================================================

-- Create Base Helper Function for API calls (kept for backwards compatibility)
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST(
  path STRING, 
  environment STRING DEFAULT 'production1',
  query_params VARIANT DEFAULT NULL
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'make_api_request'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

def make_api_request(path, environment, query_params=None):
    try:
        # Get OAuth token directly
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return {"error": "Failed to obtain OAuth token"}

        # Allow selection between production and authoring environments
        base_url = f"https://ontology.onelondon.online/{environment}/fhir"
        url = f"{base_url}/{path}"

        # Prepare headers
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }

        # Convert variant to dict if needed
        params = None
        if query_params is not None:
            try:
                if isinstance(query_params, str):
                    params = json.loads(query_params)
                else:
                    params = dict(query_params) if query_params else None
            except (TypeError, ValueError):
                params = None

        # Make request
        response = requests.get(url, headers=headers, params=params)

        # Check for errors
        response.raise_for_status()

        return response.json()
    except requests.exceptions.RequestException as e:
        # Handle request errors
        error_message = str(e)
        response_text = getattr(e.response, 'text', 'No response text')

        return {
            "error": "API request failed", 
            "details": error_message,
            "response": response_text
        }
    except Exception as e:
        # Handle any other errors
        return {"error": "Unexpected error", "details": str(e)}
$$;

-- Debug function to test OAuth token retrieval
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.DEBUG_AUTH()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'debug_oauth'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

def debug_oauth():
    try:
        # Test getting OAuth token
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return {"error": "No access token returned", "token": None}
        
        # Test the token by making requests to both endpoints
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }
        
        # Test metadata endpoint (known to work)
        metadata_response = requests.get('https://ontology.onelondon.online/authoring/fhir/metadata', headers=headers)
        
        # Test the specific ValueSet endpoint (failing)
        vs_response = requests.get('https://ontology.onelondon.online/authoring/fhir/ValueSet/59a3b2ff-712c-4015-b518-49aab287e535', headers=headers)
        
        return {
            "token_received": bool(access_token),
            "token_length": len(access_token) if access_token else 0,
            "token_prefix": access_token[:10] + "..." if access_token and len(access_token) > 10 else access_token,
            "metadata_status": metadata_response.status_code,
            "metadata_ok": metadata_response.ok,
            "valueset_status": vs_response.status_code,
            "valueset_ok": vs_response.ok,
            "valueset_response": vs_response.text[:200] if vs_response.text else "No response text"
        }
    except Exception as e:
        return {"error": "Debug failed", "details": str(e)}
$$;

-- Create VS_CODES a simple array function to return codes in a valueset as an array
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_CODES(
  value_set_id STRING, 
  environment STRING DEFAULT 'production1'
)
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_codes_from_value_set'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

def get_codes_from_value_set(value_set_id, environment):
    try:
        # Get OAuth token directly
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return []

        # Make API call directly
        base_url = f"https://ontology.onelondon.online/{environment}/fhir"
        url = f"{base_url}/ValueSet/{value_set_id}/$expand"

        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }

        response = requests.get(url, headers=headers)
        response.raise_for_status()
        
        result = response.json()

        # Extract just the codes as an array
        codes = []
        if isinstance(result, dict) and 'expansion' in result and 'contains' in result['expansion']:
            for item in result['expansion']['contains']:
                codes.append(item.get('code', ''))

        return codes
    except Exception as e:
        return []  # Return empty array on error
$$;

-- Create detailed function to return a structured table object
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS(
  value_set_id STRING, 
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING, display STRING, system STRING)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_codes_from_value_set_detailed'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

class get_codes_from_value_set_detailed:
    def process(self, value_set_id, environment):
        try:
            # Get OAuth token directly
            access_token = _snowflake.get_oauth_access_token('cred')
            
            if not access_token:
                return  # Return nothing on error

            # Make API call directly
            base_url = f"https://ontology.onelondon.online/{environment}/fhir"
            url = f"{base_url}/ValueSet/{value_set_id}/$expand"

            headers = {
                'Authorization': f'Bearer {access_token}',
                'Accept': 'application/fhir+json'
            }

            response = requests.get(url, headers=headers)
            response.raise_for_status()
            
            result = response.json()
            
            # Extract codes from the expansion with all details
            if isinstance(result, dict) and 'expansion' in result and 'contains' in result['expansion']:
                for item in result['expansion']['contains']:
                    yield (
                        item.get('code', ''),
                        item.get('display', ''),
                        item.get('system', '')
                    )
        except Exception as e:
            # Return nothing on error
            return
$$;

-- Function to return a raw JSON response
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(
  value_set_id STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_value_set_raw'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

def get_value_set_raw(value_set_id, environment):
    try:
        # Get OAuth token directly
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return {"error": "Failed to obtain OAuth token"}

        # Make API call directly
        base_url = f"https://ontology.onelondon.online/{environment}/fhir"
        url = f"{base_url}/ValueSet/{value_set_id}"

        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }

        response = requests.get(url, headers=headers)
        response.raise_for_status()
        
        return response.json()
    except Exception as e:
        return {"error": "Failed to retrieve ValueSet", "details": str(e)}
$$;

-- ValueSet Search Function
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_SEARCH(
  search_term STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(id STRING, url STRING, name STRING, title STRING, status STRING)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'search_value_sets'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
import json

class search_value_sets:
    def process(self, search_term, environment):
        try:
            # Get OAuth token directly
            access_token = _snowflake.get_oauth_access_token('cred')
            
            if not access_token:
                return  # Return nothing on error

            # Make API call directly
            base_url = f"https://ontology.onelondon.online/{environment}/fhir"
            url = f"{base_url}/ValueSet"

            headers = {
                'Authorization': f'Bearer {access_token}',
                'Accept': 'application/fhir+json'
            }
            
            params = {"name": search_term}

            response = requests.get(url, headers=headers, params=params)
            response.raise_for_status()
            
            result = response.json()
            
            # Extract ValueSet metadata from the search results
            if isinstance(result, dict) and 'entry' in result:
                for entry in result['entry']:
                    if 'resource' in entry and entry['resource']['resourceType'] == 'ValueSet':
                        vs = entry['resource']
                        yield (
                            vs.get('id', ''),
                            vs.get('url', ''),
                            vs.get('name', ''),
                            vs.get('title', ''),
                            vs.get('status', '')
                        )
        except Exception as e:
            # Return nothing on error
            return
$$;

-- ECL Query Function - Returns codes matching an ECL expression
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING, display STRING, system STRING)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'execute_ecl_query'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests', 'urllib3')
AS $$
import _snowflake
import requests
import json
from urllib.parse import quote

class execute_ecl_query:
    def process(self, ecl_expression, environment):
        try:
            # Get OAuth token directly
            access_token = _snowflake.get_oauth_access_token('cred')
            
            if not access_token:
                return  # Return nothing on error

            # URL encode the ECL expression
            encoded_ecl = quote(ecl_expression, safe='')
            
            # Construct the full URL parameter for the ValueSet expansion
            url_param = f"http://snomed.info/sct?fhir_vs=ecl/{encoded_ecl}"
            
            # Make API call directly
            base_url = f"https://ontology.onelondon.online/{environment}/fhir"
            url = f"{base_url}/ValueSet/$expand"

            headers = {
                'Authorization': f'Bearer {access_token}',
                'Accept': 'application/fhir+json'
            }
            
            params = {"url": url_param}

            response = requests.get(url, headers=headers, params=params)
            response.raise_for_status()
            
            result = response.json()
            
            # Extract codes from the expansion
            if isinstance(result, dict) and 'expansion' in result and 'contains' in result['expansion']:
                for item in result['expansion']['contains']:
                    yield (
                        item.get('code', ''),
                        item.get('display', ''),
                        item.get('system', '')
                    )
        except Exception as e:
            # Return nothing on error
            return
$$;

-- ECL Query Simple - Returns just the codes as an array
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS ARRAY
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_ecl_codes'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests', 'urllib3')
AS $$
import _snowflake
import requests
import json
from urllib.parse import quote

def get_ecl_codes(ecl_expression, environment):
    try:
        # Get OAuth token directly
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return []

        # URL encode the ECL expression
        encoded_ecl = quote(ecl_expression, safe='')
        
        # Construct the full URL parameter for the ValueSet expansion
        url_param = f"http://snomed.info/sct?fhir_vs=ecl/{encoded_ecl}"
        
        # Make API call directly
        base_url = f"https://ontology.onelondon.online/{environment}/fhir"
        url = f"{base_url}/ValueSet/$expand"

        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }
        
        params = {"url": url_param}

        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        
        result = response.json()
        
        # Extract just the codes as an array
        codes = []
        if isinstance(result, dict) and 'expansion' in result and 'contains' in result['expansion']:
            for item in result['expansion']['contains']:
                codes.append(item.get('code', ''))
        
        return codes
    except Exception as e:
        return []  # Return empty array on error
$$;

-- ECL Query Raw - Returns full FHIR JSON response for ECL queries
CREATE OR REPLACE SECURE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'get_ecl_raw'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests', 'urllib3')
AS $$
import _snowflake
import requests
import json
from urllib.parse import quote

def get_ecl_raw(ecl_expression, environment):
    try:
        # Get OAuth token directly
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return {"error": "Failed to obtain OAuth token"}

        # URL encode the ECL expression
        encoded_ecl = quote(ecl_expression, safe='')
        
        # Construct the full URL parameter for the ValueSet expansion
        url_param = f"http://snomed.info/sct?fhir_vs=ecl/{encoded_ecl}"
        
        # Make API call directly
        base_url = f"https://ontology.onelondon.online/{environment}/fhir"
        url = f"{base_url}/ValueSet/$expand"

        headers = {
            'Authorization': f'Bearer {access_token}',
            'Accept': 'application/fhir+json'
        }
        
        params = {"url": url_param}

        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()
        
        return response.json()
    except Exception as e:
        return {"error": "Failed to execute ECL query", "details": str(e)}
$$;

-- =====================================================
-- USAGE EXAMPLES
-- =====================================================
-- Example 1: Using VS_CODES in an IN clause
/*
SELECT * 
FROM patient_diagnoses
WHERE diagnosis_code IN (EXTERNAL_ACCESS.ONTOSERVER.VS_CODES('b407edf8-5125-40a8-9742-44c0425709bd'));
*/

-- Example 2: Using ECL_CODES in an IN clause for diabetes-related conditions
/*
SELECT * 
FROM patient_diagnoses
WHERE diagnosis_code IN (EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009'));
*/

-- Example 3: Joining with VS_DETAILS for enriched data
/*
SELECT 
    pd.patient_id,
    pd.diagnosis_code,
    vsc.display as diagnosis_name,
    vsc.system
FROM patient_diagnoses pd
INNER JOIN TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS('b407edf8-5125-40a8-9742-44c0425709bd')) vsc
    ON pd.diagnosis_code = vsc.code;
*/

-- Example 4: Creating a view with ValueSet codes
/*
CREATE OR REPLACE VIEW diabetes_codes AS
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<< 73211009 | Diabetes mellitus |'));
*/

-- Example 5: Getting full FHIR JSON response for ECL query
/*
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('<< 73211009 | Diabetes mellitus |', 'authoring');
*/

-- Example 6: Getting detailed ECL results with structured data
/*
SELECT * 
FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<< 73211009 | Diabetes mellitus |', 'authoring'))
WHERE display LIKE '%type%';
*/

-- Example 7: Getting raw ValueSet JSON for analysis
/*
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('b407edf8-5125-40a8-9742-44c0425709bd', 'authoring');
*/