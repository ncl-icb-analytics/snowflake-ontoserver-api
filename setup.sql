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
  OAUTH_CLIENT_ID = 'your-client-id-here'
  OAUTH_CLIENT_SECRET = 'your-client-secret-here'
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
        status_code = getattr(e.response, 'status_code', 'Unknown')
        response_text = getattr(e.response, 'text', 'No response text')

        return {
            "error": "API request failed", 
            "status_code": status_code,
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

-- =====================================================
-- RAW FUNCTIONS (Base functions that return JSON)
-- =====================================================

-- Function to return a raw JSON response
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(
  value_set_id STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS VARIANT
LANGUAGE SQL
AS $$
  SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST(
    CONCAT('ValueSet/', value_set_id), 
    environment, 
    NULL
  )
$$;

-- ECL Query Raw - Returns full FHIR JSON response for ECL queries
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
HANDLER = 'ecl_raw'
EXTERNAL_ACCESS_INTEGRATIONS = (onto_api_integration)
SECRETS = ('cred' = EXTERNAL_ACCESS.ONTOSERVER.onto_oauth_secret)
PACKAGES = ('requests')
AS $$
import _snowflake
import requests
from urllib.parse import quote

def ecl_raw(ecl_expression, environment):
    try:
        access_token = _snowflake.get_oauth_access_token('cred')
        
        if not access_token:
            return {"error": "Failed to obtain OAuth token"}

        # Properly URL encode the ECL expression
        encoded_ecl = quote(ecl_expression, safe='')
        url_param = f"http://snomed.info/sct?fhir_vs=ecl/{encoded_ecl}"
        
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
    except requests.exceptions.RequestException as e:
        status_code = getattr(e.response, 'status_code', 'Unknown')
        response_text = getattr(e.response, 'text', 'No response text')
        return {
            "error": "Failed to execute ECL query", 
            "status_code": status_code,
            "details": str(e),
            "response": response_text
        }
    except Exception as e:
        return {"error": "Unexpected error", "details": str(e)}
$$;

-- =====================================================
-- PROCESSED FUNCTIONS (Functions that process the RAW data)
-- =====================================================

-- Array functions that return actual ARRAYs (useful for storing in variables or passing as parameters)
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(
  value_set_id STRING, 
  environment STRING DEFAULT 'production1'
)
RETURNS ARRAY
LANGUAGE SQL
AS $$
  SELECT ARRAY_AGG(f.value:code::STRING)
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(CONCAT(value_set_id, '/$expand'), environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_ARRAY(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS ARRAY
LANGUAGE SQL
AS $$
  SELECT ARRAY_AGG(f.value:code::STRING)
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW(ecl_expression, environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
$$;

-- Table functions that return rows (useful for JOINs and WHERE IN clauses)
-- Create VS_CODES a simple table function to return codes from a valueset
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_CODES(
  value_set_id STRING, 
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING)
LANGUAGE SQL
AS $$
  SELECT f.value:code::STRING as code
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(CONCAT(value_set_id, '/$expand'), environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
$$;

-- Create detailed function to return a structured table object
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS(
  value_set_id STRING, 
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING, display STRING, system STRING)
LANGUAGE SQL
AS $$
  SELECT 
    f.value:code::STRING as code,
    f.value:display::STRING as display,
    f.value:system::STRING as system
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(CONCAT(value_set_id, '/$expand'), environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
$$;

-- ValueSet Search Function
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.VS_SEARCH(
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

-- ECL Query Function - Returns codes matching an ECL expression with details
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING, display STRING, system STRING)
LANGUAGE SQL
AS $$
  SELECT 
    f.value:code::STRING as code,
    f.value:display::STRING as display,
    f.value:system::STRING as system
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW(ecl_expression, environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
$$;

-- ECL Query Simple - Returns just the codes as an array
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES(
  ecl_expression STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(code STRING)
LANGUAGE SQL
AS $$
  SELECT f.value:code::STRING as code
  FROM TABLE(FLATTEN(EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW(ecl_expression, environment):expansion.contains)) f
  WHERE f.value:code IS NOT NULL
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