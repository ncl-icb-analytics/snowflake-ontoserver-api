
------------------------------------------
-- ONTOSERVER API TEST PROCEDURE
-------------------------------------------
-- Creates a stored procedure to test all Ontoserver API functions

CREATE OR REPLACE PROCEDURE EXTERNAL_ACCESS.ONTOSERVER.TEST_ONTOSERVER_API()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    test_vs_id STRING DEFAULT '59a3b2ff-712c-4015-b518-49aab287e535';
    test_environment STRING DEFAULT 'authoring';
    total_tests INTEGER DEFAULT 0;
    passed_tests INTEGER DEFAULT 0;
    failed_tests INTEGER DEFAULT 0;
    output_text VARCHAR DEFAULT '';
BEGIN
    -- Create temporary table to track test results
    CREATE OR REPLACE TEMPORARY TABLE test_results (
        test_id INTEGER,
        test_name VARCHAR,
        result VARCHAR,
        error_details VARCHAR
    );
    
    -- Test 1: Base API Request
    INSERT INTO test_results
    SELECT 
        1,
        'Base API Request',
        CASE 
            WHEN EXTERNAL_ACCESS.ONTOSERVER.API_REQUEST('metadata', :test_environment):resourceType::STRING IS NOT NULL 
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        'Checking metadata endpoint on ' || :test_environment;
    
    -- Test 2: VS_CODES 
    INSERT INTO test_results
    SELECT 
        2,
        'VS_CODES Function',
        CASE WHEN ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, :test_environment)) > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Codes found: ' || ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, :test_environment));
    
    -- Test 3: VS_DETAILS
    INSERT INTO test_results
    SELECT 
        3,
        'VS_DETAILS Function',
        CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Rows returned: ' || COUNT(*)
    FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_DETAILS(:test_vs_id, :test_environment));
    
    -- Test 4: VS_SEARCH
    INSERT INTO test_results
    SELECT 
        4,
        'VS_SEARCH Function',
        CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
        'Results found: ' || COUNT(*)
    FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.VS_SEARCH('diabetes', :test_environment));
    
    -- Test 5: VS_RAW
    INSERT INTO test_results
    SELECT 
        5,
        'VS_RAW Function',
        CASE 
            WHEN EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(:test_vs_id, :test_environment):resourceType::STRING = 'ValueSet' 
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        'ResourceType: ' || COALESCE(EXTERNAL_ACCESS.ONTOSERVER.VS_RAW(:test_vs_id, :test_environment):resourceType::STRING, 'NULL');
    
    -- Test 6: Environment Parameter (test both environments)
    INSERT INTO test_results
    SELECT 
        6,
        'Environment Parameter',
        CASE 
            WHEN ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, 'production1')) >= 0 
                 AND ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, 'authoring')) > 0
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        'Prod: ' || ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, 'production1')) || 
        ' codes, Authoring: ' || ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.VS_ARRAY(:test_vs_id, 'authoring')) || ' codes';
    
    -- Test 7: ECL Details
    INSERT INTO test_results
    SELECT 
        7,
        'ECL Details Function',
        CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
        'ECL results: ' || COUNT(*)
    FROM TABLE(EXTERNAL_ACCESS.ONTOSERVER.ECL_DETAILS('< 73211009 | Diabetes mellitus |', :test_environment));
    
    -- Test 8: ECL Codes
    INSERT INTO test_results
    SELECT 
        8,
        'ECL Codes Function',
        CASE WHEN ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.ECL_ARRAY('< 73211009 | Diabetes mellitus |', :test_environment)) > 0 
        THEN 'PASS' 
        ELSE 'FAIL' 
        END,
        'ECL codes found: ' || ARRAY_SIZE(EXTERNAL_ACCESS.ONTOSERVER.ECL_ARRAY('< 73211009 | Diabetes mellitus |', :test_environment));
    
    -- Test 9: ECL Raw
    INSERT INTO test_results
    SELECT 
        9,
        'ECL Raw Function',
        CASE 
            WHEN EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('< 73211009 | Diabetes mellitus |', :test_environment):resourceType::STRING = 'ValueSet' 
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        'ResourceType: ' || COALESCE(EXTERNAL_ACCESS.ONTOSERVER.ECL_RAW('< 73211009 | Diabetes mellitus |', :test_environment):resourceType::STRING, 'NULL');
    
    -- Calculate summary stats
    SELECT
        COUNT(*),
        SUM(CASE WHEN result = 'PASS' THEN 1 ELSE 0 END),
        SUM(CASE WHEN result = 'FAIL' THEN 1 ELSE 0 END)
    INTO
        :total_tests, :passed_tests, :failed_tests
    FROM test_results;
    
    -- Build output
    output_text := '=== ONTOSERVER API VALIDATION SUMMARY ===\n';
    output_text := output_text || 'Environment: ' || :test_environment || '\n';
    output_text := output_text || 'ValueSet ID: ' || :test_vs_id || '\n';
    output_text := output_text || 'Total Tests: ' || :total_tests || '\n';
    output_text := output_text || 'Passed: ' || :passed_tests || '\n';
    output_text := output_text || 'Failed: ' || :failed_tests || '\n';
    
    IF (:failed_tests = 0) THEN
        output_text := output_text || 'Status: ✓ SUCCESS: All tests passed!\n';
    ELSE
        output_text := output_text || 'Status: ✗ FAILURE: Some tests failed.\n';
        output_text := output_text || '\n=== FAILED TESTS ===\n';
        
        -- Add failed test details
        LET c1 CURSOR FOR 
            SELECT test_id, test_name, error_details 
            FROM test_results 
            WHERE result = 'FAIL' 
            ORDER BY test_id;
        FOR record IN c1 DO
            output_text := output_text || 'Test ' || record.test_id || ': ' || record.test_name || ' - ' || record.error_details || '\n';
        END FOR;
    END IF;
    
    -- Add all test details
    output_text := output_text || '\n=== ALL TEST DETAILS ===\n';
    LET c2 CURSOR FOR 
        SELECT test_id, test_name, result, error_details 
        FROM test_results 
        ORDER BY test_id;
    FOR record IN c2 DO
        output_text := output_text || 'Test ' || record.test_id || ': ' || record.test_name || ' - ' || record.result || ' (' || record.error_details || ')\n';
    END FOR;
    
    -- Clean up
    DROP TABLE IF EXISTS test_results;
    
    -- Return the output
    RETURN output_text;
END;
$$;


-- Call the procedure to test the integration
CALL EXTERNAL_ACCESS.ONTOSERVER.TEST_ONTOSERVER_API();
