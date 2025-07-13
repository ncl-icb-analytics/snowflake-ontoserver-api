# Snowflake Ontoserver API Integration

This project provides setup scripts and Snowflake functions to integrate with the One London Ontoserver FHIR API, enabling seamless access to terminology services from within Snowflake.

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

Ensure you have a database for the integration. We recommend using `EXTERNAL_ACCESS` for consistency with governance best practices, but you can use any database name:

```sql
-- Run as ACCOUNTADMIN if database doesn't exist
CREATE DATABASE IF NOT EXISTS EXTERNAL_ACCESS;
-- OR use your preferred database name:
-- CREATE DATABASE IF NOT EXISTS YOUR_DATABASE_NAME;
```

The setup script will automatically create an `ONTOSERVER` schema within your chosen database to contain all schema-level objects.

**Note**: If you use a different database name, find/replace all `EXTERNAL_ACCESS.` (with dot) in the SQL files to match your chosen database name.

### 3. Configure and Run Setup Script

1. Edit the `setup.sql` file and update the OAuth credentials:

```sql
-- Update these lines in setup.sql:
OAUTH_CLIENT_ID = 'your-client-id-here'
OAUTH_CLIENT_SECRET = 'your-client-secret-here'
```

2. If using a different database name, update all references to `EXTERNAL_ACCESS` in the SQL files.

3. Execute the setup script as ACCOUNTADMIN:

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

### Governance Considerations

We recommend using a dedicated `EXTERNAL_ACCESS` database.

While you can use any database name, keeping external access integrations together simplifies governance.

All schema-level objects related to this integration will be placed in a `ONTOSERVER` schema.

While you can use any database name, keeping external access integrations together simplifies governance.

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

**Function parameters:**
- `environment`: 'authoring' (latest content) or 'production1' (stable, default)
- All functions return empty results on error

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
