# Snowflake Ontoserver API Integration

This project provides Snowflake functions to interact with the NHS North Central London (NCL) Ontoserver FHIR API, enabling seamless access to terminology services from within Snowflake.

## Overview

The integration provides functions to:
- Query ValueSets and retrieve codes
- Execute SNOMED CT Expression Constraint Language (ECL) queries
- Search terminology resources
- Access both structured data and raw FHIR JSON responses

## How It Works

This integration leverages Snowflake's External Access capabilities to securely connect to the Ontoserver FHIR API:

1. **OAuth2 Authentication**: Uses client credentials flow to authenticate with the Ontoserver
2. **External Access Integration**: Snowflake's secure mechanism for calling external APIs
3. **Python UDFs**: Functions written in Python that handle API communication and data transformation
4. **SQL Wrapper Functions**: User-friendly SQL functions that simplify data access

## Prerequisites

- Snowflake account with ACCOUNTADMIN privileges (required for External Access setup)
- OAuth2 client credentials for Ontoserver API access
- An existing EXTERNAL_ACCESS database in your Snowflake account
- Network connectivity to ontology.onelondon.online

## Setup Instructions

### 1. Configure OAuth Credentials

First, obtain OAuth2 client credentials from your Ontoserver administrator. You'll need:
- Client ID
- Client Secret

### 2. Prepare the EXTERNAL_ACCESS Database

Ensure you have an EXTERNAL_ACCESS database created:

```sql
-- Run as ACCOUNTADMIN if database doesn't exist
CREATE DATABASE IF NOT EXISTS EXTERNAL_ACCESS;
```

### 3. Configure and Run Setup Script

1. Edit the `setup.sql` file and update the OAuth credentials:

```sql
-- Update these lines in setup.sql:
OAUTH_CLIENT_ID = 'your-client-id-here'
OAUTH_CLIENT_SECRET = 'your-client-secret-here'
```

2. Execute the setup script as ACCOUNTADMIN:

```sql
-- Run the entire setup.sql file
```

### 4. Created Snowflake Objects

The setup script creates these essential components:
- **Network Rule**: Allows secure connections to ontology.onelondon.online
- **Security Integration**: Handles OAuth2 authentication with the Ontoserver
- **Secret**: Securely stores OAuth credentials
- **External Access Integration**: Combines network and authentication rules
- **Functions**: Complete set of Python and SQL functions for API access

### 5. Verify Installation

Run the test procedure to verify everything is working:

```sql
CALL EXTERNAL_ACCESS.ONTOSERVER.TEST_ONTOSERVER_API();
```

## Architecture

### Security Model

- All API credentials are stored securely using Snowflake secrets
- Network access is restricted to the Ontoserver domain only
- Functions use Snowflake's secure external access framework
- No credentials are exposed in code or logs

### Function Types

1. **Array Functions** (`_CODES`): Return simple arrays for IN clause filtering
2. **Table Functions** (`_DETAILS`): Return structured tables with full metadata
3. **Raw Functions** (`_RAW`): Return complete FHIR JSON responses
4. **Utility Functions**: Helper functions for authentication and debugging

## Available Functions

### ValueSet Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `VS_CODES` | Array | Simple array of codes from a ValueSet |
| `VS_DETAILS` | Table | Structured table with code, display, and system |
| `VS_RAW` | JSON | Full FHIR ValueSet JSON response |
| `VS_SEARCH` | Table | Search for ValueSets by name |

### ECL (Expression Constraint Language) Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `ECL_CODES` | Array | Simple array of codes matching ECL expression |
| `ECL_DETAILS` | Table | Structured table with code, display, and system |
| `ECL_RAW` | JSON | Full FHIR ValueSet expansion JSON response |

### Utility Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `API_REQUEST` | JSON | General GET request to any Ontoserver endpoint |
| `DEBUG_AUTH` | JSON | Debug OAuth authentication status |

## Function Reference

### VS_CODES(value_set_id, environment)

Returns a simple array of codes from a ValueSet.

**Parameters:**
- `value_set_id` (STRING): The ValueSet ID or URL
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** ARRAY of codes

**Example:**
```sql
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_CODES('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring');
-- Returns: ["73211009", "44054006", "46635009", ...]
```

**Usage in queries:**
```sql
-- Find patients with diabetes codes
SELECT * 
FROM patient_diagnoses
WHERE diagnosis_code IN (EXTERNAL_ACCESS.ONTOSERVER.VS_CODES('diabetes-valueset-id'));
```

### VS_DETAILS(value_set_id, environment)

Returns detailed information about codes in a ValueSet.

**Parameters:**
- `value_set_id` (STRING): The ValueSet ID or URL
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** TABLE(code STRING, display STRING, system STRING)

**Example:**
```sql
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring'));
```

**Result:**
| code | display | system |
|------|---------|--------|
| 73211009 | Diabetes mellitus | http://snomed.info/sct |
| 44054006 | Diabetes mellitus type 2 | http://snomed.info/sct |

**Usage in queries:**
```sql
-- Enrich patient data with terminology descriptions
SELECT 
    pd.patient_id,
    pd.diagnosis_code,
    vs.display as diagnosis_name,
    vs.system
FROM patient_diagnoses pd
INNER JOIN TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS('diabetes-valueset-id')) vs
    ON pd.diagnosis_code = vs.code;
```

### VS_RAW(value_set_id, environment)

Returns the complete FHIR ValueSet resource as JSON.

**Parameters:**
- `value_set_id` (STRING): The ValueSet ID or URL
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** VARIANT (JSON object)

**Example:**
```sql
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring');
```

**Usage:**
```sql
-- Extract specific metadata from ValueSet
SELECT 
    vs_data:id::STRING as valueset_id,
    vs_data:name::STRING as valueset_name,
    vs_data:title::STRING as valueset_title,
    vs_data:status::STRING as status
FROM (
    SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('diabetes-valueset-id') as vs_data
);
```

### VS_SEARCH(search_term, environment)

Search for ValueSets by name.

**Parameters:**
- `search_term` (STRING): Search term to match ValueSet names
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** TABLE(id STRING, url STRING, name STRING, title STRING, status STRING)

**Example:**
```sql
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_SEARCH('diabetes', 'authoring'));
```

### ECL_CODES(ecl_expression, environment)

Execute a SNOMED CT ECL expression and return matching codes as an array.

**Parameters:**
- `ecl_expression` (STRING): SNOMED CT Expression Constraint Language expression
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** ARRAY of codes

**Examples:**
```sql
-- Get all diabetes-related codes
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009 | Diabetes Mellitus |');

-- Specific diabetes types
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('
<< 44054006 | Type 2 Diabetes | OR << 46635009 | Type 1 Diabetes |
');

-- Include historical concepts
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009 | Diabetes Mellitus | {{ +HISTORY-MAX }}');
```

**Usage in queries:**
```sql
-- Find patients with any type of diabetes
SELECT * 
FROM patient_diagnoses
WHERE diagnosis_code IN (EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009 | Diabetes Mellitus |'));
```

### ECL_DETAILS(ecl_expression, environment)

Execute ECL expression and return detailed code information.

**Parameters:**
- `ecl_expression` (STRING): SNOMED CT Expression Constraint Language expression
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** TABLE(code STRING, display STRING, system STRING)

**Examples:**
```sql
-- Basic descendants query
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<< 73211009 | Diabetes Mellitus |'));

-- Multiple concept types
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 44054006 | Type 2 Diabetes | OR << 46635009 | Type 1 Diabetes |
'));

-- Include historical concepts
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 73211009 | Diabetes Mellitus | {{ +HISTORY-MAX }}
'));
```

### ECL_RAW(ecl_expression, environment)

Execute ECL expression and return the full FHIR expansion response.

**Parameters:**
- `ecl_expression` (STRING): SNOMED CT Expression Constraint Language expression
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')

**Returns:** VARIANT (JSON object)

**Examples:**
```sql
-- Get full expansion response for diabetes
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('<< 73211009 | Diabetes Mellitus |');

-- Complex query with multiple types
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('
<< 44054006 | Type 2 Diabetes | OR << 46635009 | Type 1 Diabetes |
');
```

### API_REQUEST(path, environment, query_params)

Low-level function for GET requests to any Ontoserver FHIR endpoint.

**Parameters:**
- `path` (STRING): API path (e.g., 'metadata', 'ValueSet/123')
- `environment` (STRING): 'authoring' or 'production1' (default: 'production1')
- `query_params` (VARIANT): Optional query parameters as JSON object

**Returns:** VARIANT (JSON object)

**Limitations:**
- **GET requests only** - Cannot perform POST, PUT, DELETE operations
- **Read-only access** - Cannot create or modify FHIR resources
- **Restricted access** - May require specific permissions

**Example:**
```sql
-- Get server metadata
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('metadata', 'authoring', NULL);

-- Get ValueSet with query parameters
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST(
    'ValueSet', 
    'authoring', 
    PARSE_JSON('{"name": "diabetes"}')
);
```

## Environments

Two environments are available:

- **authoring**: Latest terminology content under development (primarily for ValueSet operations)
- **production1**: Stable, production-ready terminology content (default, recommended for ECL queries)

**Environment Usage Guidelines:**
- **ECL queries**: Use default `production1` for stable SNOMED CT content
- **ValueSet operations**: Use `authoring` for latest ValueSet definitions, `production1` for stable releases
- **Production systems**: Always use `production1` for consistent results

## Common ECL Patterns

| Pattern | Description | Example |
|---------|-------------|---------|
| `<< CONCEPTID` | All descendants of concept | `<< 73211009` (all types of diabetes) |
| `< CONCEPTID` | Direct children only | `< 73211009` (direct subtypes) |
| `>> CONCEPTID` | All ancestors | `>> 44054006` (all parents of T2DM) |
| `CONCEPTID1 OR CONCEPTID2` | Either concept | `73211009 OR 44054006` |
| `<< CONCEPTID {{ +HISTORY-MAX }}` | Include inactive concepts | `<< 73211009 {{ +HISTORY-MAX }}` |
| `<< CONCEPTID \| Term \|` | Descendants with term | `<< 73211009 \| Diabetes Mellitus \|` |
| `CONCEPT1 OR CONCEPT2` | Multiple concepts | `<< 44054006 \| Type 2 Diabetes \| OR << 46635009 \| Type 1 Diabetes \|` |

### Advanced ECL Examples

**Basic diabetes descendants:**
```sql
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<< 73211009 | Diabetes Mellitus |'));
```

**Specific diabetes types:**
```sql
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 44054006 | Type 2 Diabetes | OR << 46635009 | Type 1 Diabetes |
'));
```

**Include inactive/historical concepts:**
```sql
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 73211009 | Diabetes Mellitus | {{ +HISTORY-MAX }}
'));
```

**Complex expressions with attributes:**
```sql
-- Diabetes with specific finding sites
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 73211009 | Diabetes Mellitus | : 363698007 | Finding site | = << 113331007 | Endocrine system |
'));
```

## Error Handling

Functions return empty arrays/tables or error objects on failure:

```sql
-- Check for errors
SELECT 
    CASE 
        WHEN result:error IS NOT NULL 
        THEN 'Error: ' || result:error::STRING 
        ELSE 'Success' 
    END as status
FROM (
    SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('invalid-id') as result
);
```

## Performance Tips

1. **Use appropriate function type**: 
   - Use `_CODES` functions for simple IN clause lookups (returns array)
   - Use `_DETAILS` functions for enrichment with display names (returns table)
   - Use `_RAW` functions for metadata analysis (returns JSON)

2. **Array vs Table functions**:
   - For IN clauses: Use arrays directly: `WHERE code IN (VS_CODES(...))`
   - For JOINs: Use table functions: `JOIN TABLE(VS_DETAILS(...))`

3. **Cache results**: Store frequently used ValueSet expansions in tables
4. **Batch operations**: Process multiple codes in single queries where possible
5. **Environment selection**: Use 'production1' for production workloads

## Creating Views

Create reusable views for common terminology sets:

```sql
-- Create a diabetes codes view using table expansion
CREATE OR REPLACE VIEW diabetes_codes AS
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<< 73211009'));

-- Use the view for lookups
SELECT * FROM patient_diagnoses 
WHERE diagnosis_code IN (SELECT code FROM diabetes_codes);

-- Or use the array function directly (more efficient)
SELECT * FROM patient_diagnoses 
WHERE diagnosis_code IN (EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009'));
```

## Testing

Run the comprehensive test procedure:

```sql
CALL EXTERNAL_ACCESS.ONTOSERVER.TEST_ONTOSERVER_API();
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your user has access to the EXTERNAL_ACCESS schema
2. **Empty Results**: Check ValueSet ID and environment parameter
3. **Timeout**: Large ValueSets may take time to expand

### Debug Authentication

```sql
SELECT EXTERNAL_ACCESS.ONTOSERVER.DEBUG_AUTH();
```

## Support

For issues with:
- **Function errors**: Check test results and debug authentication
- **SNOMED CT content**: Contact terminology team
- **Access permissions**: Contact Snowflake administrators