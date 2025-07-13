-- 0. Debug OAuth token retrieval first
SELECT EXTERNAL_ACCESS.ONTOSERVER.DEBUG_AUTH();

-- 1. Test the base API request directly to see the raw response
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('metadata', 'authoring', NULL);

-- 2. Check if we're getting any error in the response
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('metadata', 'authoring', NULL):error;

-- 3a. Test the same ValueSet URL using API_REQUEST (with explicit NULL for query_params)
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('ValueSet/59a3b2ff-712c-4015-b518-49aab287e535', 'authoring', NULL);

-- 3b. Test VS_RAW to see the full response for the ValueSet
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring');

-- 4. Check if there's an error in the VS_RAW response
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_RAW('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring'):error;

-- 5. Try VS_CODES to see if we get an empty array or an error
SELECT EXTERNAL_ACCESS.ONTOSERVER.VS_CODES('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring');

-- 6. Try a simple ValueSet search
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_SEARCH('test', 'authoring'));

-- 7. Test with production1 to see if it's environment-specific
SELECT EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('metadata', 'production1');

-- 8. Try VS_DETAILS to see if we get any rows
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS('59a3b2ff-712c-4015-b518-49aab287e535', 'authoring'));

-- 9. Test ECL with a simple expression
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_CODES('((<< 48694002 {{ +HISTORY-MAX }}) OR (<< 35489007 {{ +HISTORY-MAX }}))', 'authoring');

-- 10. Test new ECL_RAW function
SELECT EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('73211009', 'authoring');

-- 11. Test ECL_DETAILS (renamed from ECL_QUERY)
SELECT * FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('((<< 48694002 {{ +HISTORY-MAX }}) OR (<< 35489007 {{ +HISTORY-MAX }}))', 'authoring'));

-- 12. Check the full URL being called (debug query)
SELECT 'https://ontology.onelondon.online/authoring/fhir/metadata' as debug_url;