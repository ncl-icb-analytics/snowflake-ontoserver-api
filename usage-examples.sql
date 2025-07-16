-- ONTOSERVER FHIR API Usage Examples
-- ======================================
-- The Shrimp browser [https://ontoserver.csiro.au/shrimp/launch.html?iss=https://ontology.onelondon.online/authoring/fhir] 
-- can help you build ECL expressions
-- You can log in using your NHS Mail account (choose Microsoft Account).
-- termbrowser.nhs.uk is best for exploring concepts and their relationships

-- Key ECL Operators
-- ======================================
-- (no operator) = the concept itself only
-- << means "descendant or self of" - returns the concept and all its subtypes
-- < means "descendant of" - returns only the subtypes (not the concept itself)
-- >> means "ancestor or self of" - returns the concept and all its parent concepts  
-- > means "ancestor of" - returns only the parent concepts
-- * means "any concept" - useful in relationship queries
-- ! means "not" - excludes concepts
-- ^ means "member of" - for reference sets
-- MINUS, AND, OR and () are used in logical operations
-- Note: ECL queries always return a distinct list

-- ⚠️ WARNING: The terminology server has a maximum limit of 50,000 codes per request
-- Queries that would return more will error.

-- Basic ECL Examples
-- ======================================
-- Return a list of type 2 diabetes codes as a Table
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('<<44054006 | Type 2 Diabetes |'));

-- You can also return those codes in an array format, useful when you need all codes
-- as a single value (e.g. storing codes in a variable or passing as a parameter)
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_ARRAY('<<44054006 | Type 2 Diabetes |');

-- Tip: Text between pipes |...| is optional and can include anything you want. It helps make the code readable.
-- SNOMED only processes the numeric codes and operators

-- You can also use ECL_DETAILS to return the code, display and system for each concept
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('<<1003671000000109')); -- HbA1c Level

-- Using reference sets: Find all safeguarding-related issues
SELECT code, display FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '^ 999002381000000108 | Safeguarding issues simple reference set |'
    )
); -- You can search for other reference sets using https://termbrowser.nhs.uk/

-- You can also view the raw JSON response from the terminology server with ECL_RAW
-- Useful for debugging or if you want additional metadata
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('<< 110359009 | Learning disability |');
-- Returns the complete FHIR ValueSet expansion with all metadata

-- Return blood pressure codes including historical terms
-- {{ +HISTORY-MAX }} includes inactive concepts that may have been used in old patient records
-- HISTORY-MIN: only concepts marked as SAME AS or MOVED FROM (high confidence)
-- HISTORY-MOD: adds REPLACED BY relationships (moderate confidence)
-- HISTORY-MAX: adds POSSIBLY EQUIVALENT TO relationships (casts widest net)
-- Usually for population health we want to use HISTORY-MAX to be as inclusive as possible and not miss patients
-- Including historical terms is important when using old data where codes have not been updated; as our data might be using legacy terms.
SELECT * FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES(
        '<<271649006 | Systolic BP | {{ +HISTORY-MAX }} OR <<271650006 | Diastolic BP | {{ +HISTORY-MAX }}'
    )
);

-- Find all diabetes codes except gestational diabetes
SELECT * FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '<< 73211009 | Diabetes | MINUS << 11687002 | Gestational diabetes |'
    )
); -- use the MINUS operator for exclusions

-- Using ECL to filter data
-- ======================================
-- Select A&E EncounterDiagnosis from SUS for DVT
-- Example 1: Using a subquery
SELECT * 
FROM "SUS"."AE"."EncounterDiagnosisSNOMED"
WHERE "Code" IN (
    SELECT code 
    FROM TABLE(
        EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES(
            '<<128053003 | Deep Vein Thrombosis |'
        )
    )
);

-- Example 2: Using a CTE with JOIN (useful when building complex logic)
WITH dvt_codes AS (
    SELECT code 
    FROM TABLE(
        EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES(
            '<<128053003 | Deep Vein Thrombosis |'
        )
    )
)
SELECT e.* 
FROM "SUS"."AE"."EncounterDiagnosisSNOMED" e
JOIN dvt_codes d ON e."Code" = d.code;

-- Medication Queries
-- ======================================
-- Most medication-related queries will require using relationships to get meaningful results
-- ECL relationship syntax: * : relationship = target
-- This translates to: "any concept that has a specific relationship with the target concept"

-- Example: Find all medications containing ibuprofen
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '* : 10362801000001104 | Has specific active ingredient | = 387207008 | Ibuprofen (substance) |'
    )
); -- Tip: always use the (substance) labelled codes for the target concept for these relationship queries

-- Using << with relationships: Find medications containing any type of insulin
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '* : 10362801000001104 | Has specific active ingredient | = << 67866001 | Insulin (substance) |'
    )
);

-- Combination products: Find medications containing BOTH paracetamol AND codeine (co-codamol)
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '* : 10362801000001104 = 387517004 | Paracetamol |, 10362801000001104 = 261000 | Codeine |'
    )
); -- The comma between conditions means AND

-- Alternative products: Find medications containing all forms of Valproate
-- Useful for capturing all salt forms/variants of the same medication
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '(* : 10362801000001104 | Has specific active ingredient | = 264325000 | Valproate |) OR
         (* : 10362801000001104 | Has specific active ingredient | = 387481005 | Sodium valproate |) OR
         (* : 10362801000001104 | Has specific active ingredient | = 387080000 | Valproic acid |) OR
         (* : 10362801000001104 | Has specific active ingredient | = 5641004 | Valproate semisodium |)'
    )
);
-- This ensures you don't miss patients on different formulations of the same drug
-- Brackets group each condition; OR returns products from each

-- Advanced ECL Examples
-- ======================================

-- Select secondary hypertension codes, where hypertension is caused by another disease
-- Potentially curable and often requires different treatment to primary (essential) hypertension
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
'(<< 38341003 | Hypertensive disorder | : 42752001 | Due to | = *) OR (<<31992008 | Secondary Hypertension |)'
    )
);

-- All infections with viral causative agents
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
'<< 40733004 | Infectious disease | : 246075003 | Causative agent | = << 49872002 | Virus |'
    )
); -- you could easily modify this to find diseases caused by specific pathogens, like SARS-CoV-2, MRSA or E. coli

-- Find adverse and allergic reactions to Penicillin
SELECT * FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
        '(<< 62014003 | Adverse reaction caused by drug | OR << 419076005 | Allergic reaction |) : 
         246075003 | Causative agent | = << 764146007 | Penicillin (substance) |'
    )
);

-- Fractures at typical osteoporotic sites, indicating possible fragility fractures
-- Hip and wrist fractures are key indicators of osteoporosis.
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('
<< 125605004 | Fracture of bone | : 363698007 | Finding site | = (
   << 29627003 | Neck of femur structure | OR
   << 75129005 | Distal radius structure |)'
   )
);

-- Concept Search
-- ======================================
-- You can search for concepts that match a specific term
-- e.g. this example searches concepts and synonyms for terms that match "ckd" and are children of Disease
SELECT * 
FROM TABLE(
    EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS(
'< 64572001 | Disease | {{ D term = "ckd" }}'
   )
); -- this is helpful for fine tuning results that are difficult to get specific enough with the model queries

-- Concept Lookup
-- ======================================
-- You can look up a specific SNOMED concept to get metadata about it and its relationships
-- Note that this only supports querying for a single concept and returns immediate relationships
-- The table format shows both codes and human-readable display names
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT('447899008')); -- Sepsis due to E. coli

-- You can access the raw JSON response too for programmatic use
SELECT EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT_RAW('447899008');

-- Filter to see just the relationships
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.LOOKUP_SCT('447899008')) 
WHERE property_display IS NOT NULL;

--  Performance tips for large or frequent use:
-- 1. Cache results to a table
--    Remember to refresh those tables regularly from a procedure or create a Dynamic Table to keep them fresh.
--    To prevent proliferation of tables, create tables that contain several code sets, covering an entire programme of work.
-- 2. Create a ValueSet in the terminology server, which gets synced to Snowflake tables
--    for faster joins without repeated API calls.
--    ValueSets are synced across London and enables shared terminology across London.
--    Like the ECL functions above, there are similar "VS" functions available for loading codes from ValueSets.
