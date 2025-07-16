# Snowflake Ontoserver API Integration

This project provides setup scripts and Snowflake functions to integrate with One London's Ontoserver FHIR API, enabling seamless access to terminology services from within Snowflake.

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
- A database for hosting the integration (we recommend `EXTERNAL_ACCESS` but any database can be used)

## Setup Instructions

### 1. Configure OAuth Credentials

First, obtain OAuth2 client credentials from your Ontoserver administrator. You'll need:
- Client ID
- Client Secret

### 2. Prepare Your Database

Ensure you have a database for the integration. We recommend using `EXTERNAL_ACCESS` to keep all external access integrations organised in one place, with separate schemas for each integration (e.g., `EXTERNAL_ACCESS.ONTOSERVER`, `EXTERNAL_ACCESS.ANOTHER_API`):

```sql
-- Run as ACCOUNTADMIN if database doesn't exist
CREATE DATABASE IF NOT EXISTS EXTERNAL_ACCESS;
-- OR use your preferred database name:
-- CREATE DATABASE IF NOT EXISTS YOUR_DATABASE_NAME;
```

The setup script will automatically create an `ONTOSERVER` schema within your chosen database to contain all schema-level objects.

**Note**: If you use a different database name, find/replace `EXTERNAL_ACCESS.` (including the dot) with `YOUR_DATABASE_NAME.` in the SQL files.

**Using a different Ontoserver**: This setup is configured for One London's Ontoserver. To use with another Ontoserver instance, find/replace all `ontology.onelondon.online` with your Ontoserver URL in `setup.sql` and update the OAuth token endpoint (line 27: `OAUTH_TOKEN_ENDPOINT`). Also verify your Ontoserver uses 'authoring' and 'production1' as environment names, or update these accordingly.

### 3. Configure and Run Setup Script

1. Edit the `setup.sql` file and update the OAuth credentials:

```sql
-- Update these lines in setup.sql:
OAUTH_CLIENT_ID = 'your-client-id-here'
OAUTH_CLIENT_SECRET = 'your-client-secret-here'
```

2. If using a different database name, update all references to `EXTERNAL_ACCESS` in the SQL files.

3. Execute the setup script as ACCOUNTADMIN:

Run the entire `setup.sql` file

### 4. Created Snowflake Objects

The setup script creates these essential components:
- **Network Rule**: Allows secure connections to ontology.onelondon.online
- **Security Integration**: Handles OAuth2 authentication with the Ontoserver API
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

#### Interaction Diagram
<img width="2458" height="1310" alt="image" src="https://github.com/user-attachments/assets/7d2e626a-adf8-4475-8661-db4869f135d7" />

### Function Architecture

The functions are organised in a clean layered architecture:

```
API_REQUEST (Python - OAuth, HTTP, ECL encoding)
    ├── VS_RAW (SQL wrapper)
    │   ├── VS_ARRAY (SQL processor)
    │   ├── VS_CODES (SQL processor) 
    │   └── VS_DETAILS (SQL processor)
    └── ECL_RAW (SQL wrapper)
        ├── ECL_ARRAY (SQL processor)
        ├── ECL_CODES (SQL processor)
        └── ECL_DETAILS (SQL processor)
```

#### Base Layer
- **`API_REQUEST`**: Core Python function handling OAuth, HTTP requests, and automatic ECL URL encoding

#### Raw Data Layer (SQL wrappers around API_REQUEST)
- **`VS_RAW`**: Calls `API_REQUEST` for ValueSet data
- **`ECL_RAW`**: Calls `API_REQUEST` with ECL expression (automatic URL encoding)

#### Processing Layer (SQL functions that process JSON from raw layer)
- **`VS_ARRAY/CODES/DETAILS`**: Process `VS_RAW` JSON into different formats
- **`ECL_ARRAY/CODES/DETAILS`**: Process `ECL_RAW` JSON into different formats

#### Function Types by Use Case
1. **Array Functions** (`_ARRAY`): Return arrays when you want a list of codes as a single value (e.g. to store as a variable)
2. **Table Functions** (`_CODES`, `_DETAILS`): Return table rows for JOINs and WHERE IN clauses
3. **Raw Functions** (`_RAW`): Return complete FHIR JSON responses for debugging/analysis
4. **Utility Functions**: Helper functions for authentication and debugging

**Key Design Benefits:**
- Single point for OAuth and HTTP logic in `API_REQUEST`
- Automatic ECL URL encoding eliminates duplication
- All functions build on the same foundation for consistency
- SQL processors are lightweight and fast

## Available Functions

### ValueSet Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `VS_ARRAY` | ARRAY | Array of codes, useful when you want to return a list of codes as a single value, like to set variables |
| `VS_CODES` | TABLE(code) | Table rows of codes for JOINs and WHERE IN |
| `VS_DETAILS` | TABLE(code, display, system) | Detailed table with full metadata |
| `VS_RAW` | VARIANT | Full FHIR ValueSet JSON response |
| `VS_SEARCH` | TABLE(id, url, name, title, status) | Search for ValueSets by name |

### ECL (Expression Constraint Language) Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `ECL_ARRAY` | ARRAY | Array of codes, useful when you want to return a list of codes as a single value, like to set variables |
| `ECL_CODES` | TABLE(code) | Table rows of codes for JOINs and WHERE IN |
| `ECL_DETAILS` | TABLE(code, display, system) | Detailed table with full metadata |
| `ECL_RAW` | VARIANT | Full FHIR ValueSet expansion JSON response |

### Concept Lookup Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `LOOKUP_SCT` | TABLE(concept_code, display, system_name, system, version, is_active, sufficiently_defined, effective_time, module_id, property_type, property_display, property_value, property_value_display, designation_language, designation_use_code, designation_use_display, designation_value) | Detailed metadata about a SNOMED CT concept with human-readable relationship names |
| `LOOKUP_SCT_RAW` | VARIANT | Raw FHIR JSON response from CodeSystem/$lookup operation |

### Utility Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `API_REQUEST` | JSON | General GET request to any Ontoserver endpoint |
| `DEBUG_AUTH` | JSON | Debug OAuth authentication status |

## Basic Usage

**ValueSet example:**
```sql
-- Get diabetes codes from a ValueSet
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_CODES('diabetes-valueset-id'));

-- Get detailed information
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS('diabetes-valueset-id'));
```

**ECL example:**
```sql
-- Find all diabetes-related codes using ECL
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009 | Diabetes Mellitus |'));

-- Include historical terms for legacy data
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<< 73211009 | Diabetes | {{ +HISTORY-MAX }}'));
```

**Concept lookup example:**
```sql
-- Get detailed metadata about a specific concept with human-readable names
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT('447899008')); -- Sepsis due to E. coli

-- Get raw FHIR JSON response
SELECT EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT_RAW('447899008');
```

**Function parameters:**
- `environment`: 'authoring' (latest content) or 'production1' (stable, default)

## ECL Quick Reference

Common ECL patterns (see [`usage-examples.sql`](usage-examples.sql) for example usage):

| Pattern | Description | Example |
|---------|-------------|---------|
| `<< CONCEPTID` | All descendants | `<< 73211009` (all diabetes types) |
| `CONCEPT1 MINUS CONCEPT2` | Exclude concepts | `<< 73211009 MINUS << 11687002` |
| `{{ +HISTORY-MAX }}` | Include historical terms | `<< 73211009 {{ +HISTORY-MAX }}` |
| `* : RELATIONSHIP = TARGET` | Medication queries | `* : 10362801000001104 = << 67866001` |

**Resources:**
- [Usage Examples](usage-examples.sql) - clinical examples using this integration
- [Shrimp Browser](https://ontoserver.csiro.au/shrimp/launch.html?iss=https://ontology.onelondon.online/authoring/fhir) - ECL builder
- [NHS Term Browser](https://termbrowser.nhs.uk) - Explore SNOMED CT concepts

## Testing and Troubleshooting

**Test installation:**
```sql
CALL EXTERNAL_ACCESS.ONTOSERVER.TEST_ONTOSERVER_API();
```

**Debug authentication:**
```sql
SELECT EXTERNAL_ACCESS.ONTOSERVER.DEBUG_AUTH();
```

## License

This repository is dual licensed under the Open Government V3 and MIT Licenses. All output subject to Crown Copyright.
