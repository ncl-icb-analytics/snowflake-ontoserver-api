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

-- Create Base Helper Function for API calls with automatic ECL encoding
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
from urllib.parse import quote
import re

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
                elif isinstance(query_params, dict):
                    params = query_params
                else:
                    # For Snowflake VARIANT objects, convert to JSON string first
                    params = json.loads(json.dumps(query_params))
            except (TypeError, ValueError, json.JSONDecodeError):
                params = None

        # Special handling for ECL queries
        if params and 'ecl_expression' in params:
            # This is an ECL query - encode the expression and build the URL parameter
            ecl_expression = params['ecl_expression']
            encoded_ecl = quote(ecl_expression, safe='')
            params = {"url": f"http://snomed.info/sct?fhir_vs=ecl/{encoded_ecl}"}

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
LANGUAGE SQL
AS $$
  SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST(
    'ValueSet/$expand',
    environment,
    OBJECT_CONSTRUCT('ecl_expression', 
      TRIM(REPLACE(REPLACE(ecl_expression, CHR(10), ' '), CHR(13), ' '))
    )
  )
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
-- CONCEPT LOOKUP FUNCTIONS
-- =====================================================

-- SNOMED CT Concept Lookup - Returns detailed metadata about a specific SNOMED concept (raw JSON)
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT_RAW(
  code STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS VARIANT
LANGUAGE SQL
AS $$
  SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST(
    'CodeSystem/$lookup',
    environment,
    OBJECT_CONSTRUCT('code', code, 'system', 'http://snomed.info/sct', 'property', '*')
  )
$$;

-- SNOMED CT Concept Lookup - Returns flattened table with concept details and display names
CREATE OR REPLACE FUNCTION EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT(
  code STRING,
  environment STRING DEFAULT 'production1'
)
RETURNS TABLE(
  concept_code STRING,
  display STRING,
  system_name STRING,
  system STRING,
  version STRING,
  is_active BOOLEAN,
  sufficiently_defined BOOLEAN,
  effective_time STRING,
  module_id STRING,
  property_type STRING,
  property_display STRING,
  property_value STRING,
  property_value_display STRING,
  designation_language STRING,
  designation_use_code STRING,
  designation_use_display STRING,
  designation_value STRING
)
LANGUAGE SQL
AS $$
  WITH lookup_result AS (
    SELECT EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT_RAW(code, environment) as result
  ),
  flattened_params AS (
    SELECT 
      result:parameter[0].valueCode::STRING as concept_code,
      result:parameter[1].valueString::STRING as display,
      result:parameter[2].valueString::STRING as system_name,
      result:parameter[3].valueUri::STRING as system,
      result:parameter[4].valueString::STRING as version,
      p.value:name::STRING as param_name,
      p.value:part[0].valueCode::STRING as part_code,
      p.value:part[1].valueCode::STRING as part_value_code,
      p.value:part[1].valueBoolean::BOOLEAN as part_value_boolean,
      p.value:part[1].valueString::STRING as part_value_string
    FROM lookup_result,
    LATERAL FLATTEN(result:parameter) p
  ),
  base_info AS (
    SELECT 
      concept_code, display, system_name, system, version,
      MAX(CASE WHEN param_name = 'property' AND part_code = 'inactive' THEN NOT part_value_boolean END) as is_active,
      MAX(CASE WHEN param_name = 'property' AND part_code = 'sufficientlyDefined' THEN part_value_boolean END) as sufficiently_defined,
      MAX(CASE WHEN param_name = 'property' AND part_code = 'effectiveTime' THEN part_value_string END) as effective_time,
      MAX(CASE WHEN param_name = 'property' AND part_code = 'moduleId' THEN part_value_code END) as module_id,
      MAX(CASE WHEN param_name = 'property' AND part_code = 'normalForm' THEN part_value_string END) as normal_form
    FROM flattened_params
    GROUP BY concept_code, display, system_name, system, version
  ),
  -- Simple properties (parent, child)
  properties AS (
    SELECT 
      bi.concept_code, bi.display, bi.system_name, bi.system, bi.version,
      bi.is_active, bi.sufficiently_defined, bi.effective_time, bi.module_id,
      fp.part_code as property_type,
      CASE fp.part_code
        WHEN 'parent' THEN 'Parent'
        WHEN 'child' THEN 'Child'
        ELSE fp.part_code
      END as property_display,
      fp.part_value_code as property_value,
      REGEXP_SUBSTR(bi.normal_form, fp.part_value_code || '\\|([^|]+)\\|', 1, 1, 'e', 1) as property_value_display,
      NULL as designation_language,
      NULL as designation_use_code,
      NULL as designation_use_display,
      NULL as designation_value
    FROM base_info bi
    JOIN flattened_params fp ON bi.concept_code = fp.concept_code
    WHERE fp.param_name = 'property'
    AND fp.part_code IN ('parent', 'child')
  ),
  -- Complex relationships from subproperties
  complex_properties AS (
    SELECT 
      bi.concept_code, bi.display, bi.system_name, bi.system, bi.version,
      bi.is_active, bi.sufficiently_defined, bi.effective_time, bi.module_id,
      sp.value:part[0].valueCode::STRING as property_type,
      REGEXP_SUBSTR(bi.normal_form, sp.value:part[0].valueCode::STRING || '\\|([^|]+)\\|', 1, 1, 'e', 1) as property_display,
      sp.value:part[1].valueCode::STRING as property_value,
      REGEXP_SUBSTR(bi.normal_form, sp.value:part[1].valueCode::STRING || '\\|([^|]+)\\|', 1, 1, 'e', 1) as property_value_display,
      NULL as designation_language,
      NULL as designation_use_code,
      NULL as designation_use_display,
      NULL as designation_value
    FROM base_info bi, lookup_result lr,
    LATERAL FLATTEN(lr.result:parameter) p,
    LATERAL FLATTEN(p.value:part) sp
    WHERE p.value:name::STRING = 'property' 
    AND p.value:part[0].valueCode::STRING = '609096000'
    AND sp.value:name::STRING = 'subproperty'
  ),
  -- Designations
  designations AS (
    SELECT 
      bi.concept_code, bi.display, bi.system_name, bi.system, bi.version,
      bi.is_active, bi.sufficiently_defined, bi.effective_time, bi.module_id,
      NULL as property_type,
      NULL as property_display,
      NULL as property_value,
      NULL as property_value_display,
      d.value:part[0].valueCode::STRING as designation_language,
      d.value:part[1].valueCoding.code::STRING as designation_use_code,
      d.value:part[1].valueCoding.display::STRING as designation_use_display,
      d.value:part[2].valueString::STRING as designation_value
    FROM base_info bi, lookup_result lr,
    LATERAL FLATTEN(lr.result:parameter) d
    WHERE d.value:name::STRING = 'designation'
  )
  SELECT * FROM properties
  UNION ALL
  SELECT * FROM complex_properties
  UNION ALL
  SELECT * FROM designations
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