create or replace PACKAGE fuma_jdr_util IS
    SUBTYPE l_string IS VARCHAR2(32767);
    TYPE lt_string_table IS TABLE OF l_string INDEX BY PLS_INTEGER;
    
    PROCEDURE list_contents (
        p_path      VARCHAR2
      , p_recursive BOOLEAN DEFAULT FALSE
      , x_jdr_path  OUT lt_string_table
    );

    PROCEDURE export_files (
        p_document  VARCHAR2
      , p_directory VARCHAR2
    );

END fuma_jdr_util;
/

CREATE OR REPLACE PACKAGE BODY fuma_jdr_util IS

    PROCEDURE do_log (
        p_log VARCHAR2
    ) IS
    BEGIN
        dbms_output.put_line(p_log);
    END do_log;

    PROCEDURE write_clob_to_file (
        p_directory IN VARCHAR2
      , p_filename  IN VARCHAR2
      , p_clob      IN CLOB
    ) IS

        l_file     utl_file.file_type;
        l_buffer   VARCHAR2(16000);
        l_amount   BINARY_INTEGER := 4000;
        l_pos      INTEGER := 1;
        l_clob_len INTEGER;
    BEGIN
        l_clob_len := dbms_lob.getlength(p_clob);
        l_file := utl_file.fopen(p_directory, p_filename, 'W');
        WHILE l_pos <= l_clob_len LOOP
            dbms_lob.read(p_clob, l_amount, l_pos, l_buffer);
            utl_file.put(l_file, l_buffer);
            l_pos := l_pos + l_amount;
        END LOOP;

        utl_file.fclose(l_file);
    EXCEPTION
        WHEN OTHERS THEN
            IF utl_file.is_open(l_file) THEN
                utl_file.fclose(l_file);
            END IF;
            RAISE;
    END write_clob_to_file;

    FUNCTION get_document_id (
        p_document VARCHAR2
      , p_type     VARCHAR2 DEFAULT 'ANY'
    ) RETURN jdr_paths.path_docid%TYPE IS

        docid    jdr_paths.path_docid%TYPE;
        pathtype jdr_paths.path_type%TYPE;
        pathseq  jdr_paths.path_seq%TYPE;
    BEGIN
        -- Get the ID of the document
        docid := jdr_mds_internal.getdocumentid(p_document);

        -- Verify that we have found a document of the correct type
        IF (
            ( docid <> -1 )
            AND ( p_type <> 'ANY' )
        ) THEN
            SELECT
                path_type
              , path_seq
            INTO
                pathtype
            , pathseq
            FROM
                jdr_paths
            WHERE
                path_docid = docid;

            IF ( p_type = 'FILE' ) THEN
                -- Make sure we are dealing with a document or package file
                IF ( (
                    pathtype = 'DOCUMENT'
                    AND pathseq = -1
                )
                OR (
                    pathtype = 'PACKAGE'
                    AND pathseq = 0
                ) ) THEN
                    RETURN ( docid );
                END IF;

            ELSIF ( p_type = 'DOCUMENT' ) THEN
                -- Make sure we are dealing with a document
                IF ( pathtype = 'DOCUMENT' ) THEN
                    RETURN ( docid );
                END IF;
            ELSIF ( p_type = 'PACKAGE' ) THEN
                IF ( pathtype = 'PACKAGE' ) THEN
                    RETURN ( docid );
                END IF;
            ELSIF ( p_type = 'PATH' ) THEN
                IF (
                    ( pathtype = 'PACKAGE' )
                    AND ( pathseq = -1 )
                ) THEN
                    RETURN ( docid );
                END IF;
            ELSIF ( p_type = 'NONPATH' ) THEN
                IF ( ( pathtype <> 'PACKAGE' )
                OR ( pathseq = 0 ) ) THEN
                    RETURN ( docid );
                END IF;
            END IF;

            -- No match found
            RETURN ( -1 );
        END IF;

        RETURN ( docid );
    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( -1 );
    END get_document_id;

    FUNCTION export_document (
        p_path      VARCHAR2
      , p_formatted NUMBER DEFAULT 0
    ) RETURN CLOB IS
        l_chunk     VARCHAR2(32000);
        l_complete  INTEGER;
        l_formatted INTEGER := p_formatted;
        x_document  CLOB;
    BEGIN
        dbms_lob.createtemporary(x_document, TRUE, dbms_lob.session);
        WHILE nvl(l_complete, 0) = 0 LOOP
            l_chunk := jdr_mds_internal.exportdocumentasxml(l_complete, p_path, l_formatted);
            IF l_chunk IS NOT NULL THEN
                dbms_lob.append(x_document, l_chunk);
            END IF;
        END LOOP;

        RETURN x_document;
    EXCEPTION
        WHEN OTHERS THEN
        -- Log the error and return whatever has been collected so far
            xxsfc_hr_exit.write_log('Error in fuma_export_document: ' || sqlerrm, 3);
            RETURN sqlerrm || dbms_utility.format_error_backtrace;
    END export_document;

    PROCEDURE list_contents (
        p_path      VARCHAR2
      , p_recursive BOOLEAN DEFAULT FALSE
      , x_jdr_path  OUT lt_string_table
    ) IS
        -- Selects documents in the current directory
        CURSOR c_docs (
            docid jdr_paths.path_docid%TYPE
        ) IS
        SELECT
            jdr_mds_internal.getdocumentname(path_docid)
          , path_type
          , path_seq
        FROM
            jdr_paths
        WHERE
                path_owner_docid = docid
            AND ( ( path_type = 'DOCUMENT'
                    AND path_seq = - 1 )
                  OR ( path_type = 'PACKAGE'
                       AND ( path_seq = 0
                             OR path_seq = - 1 ) ) );

        -- Selects documents in the current directory, plus its children
        CURSOR c_alldocs (
            docid jdr_paths.path_docid%TYPE
        ) IS
        SELECT
            jdr_mds_internal.getdocumentname(path_docid)
          , path_type
          , path_seq
        FROM
            (
                SELECT
                    path_docid
                  , path_type
                  , path_seq
                FROM
                    jdr_paths
                START WITH
                    path_owner_docid = docid
                CONNECT BY
                    PRIOR path_docid = path_owner_docid
            ) paths
        WHERE
            ( path_type = 'DOCUMENT'
              AND path_seq = - 1 )
            OR ( path_type = 'PACKAGE'
                 AND path_seq = 0 )
            OR ( path_type = 'PACKAGE'
                 AND path_seq = - 1
                 AND NOT EXISTS (
                SELECT
                    *
                FROM
                    jdr_paths
                WHERE
                    path_owner_docid = paths.path_docid
            ) );

        docid    jdr_paths.path_docid%TYPE;
        pathseq  jdr_paths.path_seq%TYPE;
        pathtype jdr_paths.path_type%TYPE;
        docname  VARCHAR2(1024);
    BEGIN
        --        dbms_output.enable(1000000);

        docid := get_document_id(p_path, 'ANY');

        -- Nothing to do if the path does not exist
        IF ( docid = -1 ) THEN
            dbms_output.put_line('Error: Could not find path ' || p_path);
            RETURN;
        END IF;

        IF ( p_recursive ) THEN
            --            dbms_output.put_line('Printing contents of '
            --                || p_path
            --                || ' recursively');
            OPEN c_alldocs(docid);
            LOOP
                FETCH c_alldocs INTO
                    docname
                , pathtype
                , pathseq;
                IF ( c_alldocs%notfound ) THEN
                    CLOSE c_alldocs;
                    EXIT;
                END IF;

                -- Make package directories distinct from files.  Note that when
                -- listing the document recursively, the only packages that are
                -- listed are the ones which contain no child documents or packages
                IF (
                    ( pathtype = 'PACKAGE' )
                    AND ( pathseq = -1 )
                ) THEN
                    docname := docname || '/';
                END IF;

                -- Print the document, but make sure it does not exceed 255 characters
                -- or else dbms_output will fail
                x_jdr_path(x_jdr_path.count + 1) := docname;
                --                WHILE (length(docname) > 255)
                --                LOOP
                --                    dbms_output.put_line(substr(docname, 1, 255));
                --                    docname := substr(docname, 256);
                --                END LOOP;
                --                dbms_output.put_line(docname);
            END LOOP;

        ELSE
            dbms_output.put_line('Printing contents of ' || p_path);
            OPEN c_docs(docid);
            LOOP
                FETCH c_docs INTO
                    docname
                , pathtype
                , pathseq;
                IF ( c_docs%notfound ) THEN
                    CLOSE c_docs;
                    EXIT;
                END IF;

                -- Make package directories distinct from files.
                IF (
                    ( pathtype = 'PACKAGE' )
                    AND ( pathseq = -1 )
                ) THEN
                    docname := docname || '/';
                END IF;

                -- Print the document, but make sure it does not exceed 255 characters
                -- or else dbms_output will fail
                x_jdr_path(x_jdr_path.count + 1) := docname;
                --                WHILE (length(docname) > 255)
                --                LOOP
                --                    dbms_output.put_line(substr(docname, 1, 255));
                --                    docname := substr(docname, 256);
                --                END LOOP;
                --                dbms_output.put_line(docname);
            END LOOP;

        END IF;

    END list_contents;

    PROCEDURE export_files (
        p_document  VARCHAR2
      , p_directory VARCHAR2
    ) IS
        l_xml_document CLOB;
        l_mapping      CLOB;
        l_file_name    l_string;
        l_dir_path     dba_directories.directory_path%TYPE;
        l_jdr_paths    lt_string_table;
        l_file_action  l_string;
    BEGIN
        SELECT directory_path INTO l_dir_path FROM dba_directories WHERE directory_name = p_directory;

        dbms_lob.createtemporary(l_mapping, TRUE);
        
        l_mapping := q'[#!/bin/bash]';
        list_contents(p_document, TRUE, l_jdr_paths);
        
        IF l_jdr_paths.count <= 0 THEN
            raise_application_error(20001, 'No document paths could be loaded.');
        END IF;
        
        FOR indx IN l_jdr_paths.first..l_jdr_paths.last LOOP
            l_file_name := substr( l_jdr_paths(indx) , instr( l_jdr_paths(indx) , '/' , -1  ) + 1) || '.' || to_char(indx, 'fm9999900') || '.xml';
            l_file_action := chr(10) || 'mv -vf ' || l_dir_path || '/' || l_file_name || ' $JAVA_TOP' || l_jdr_paths(indx) || '.xml;';

            do_log(l_jdr_paths(indx));
            dbms_lob.append(l_mapping, l_file_action);
            
            l_xml_document := export_document( l_jdr_paths(indx) );     
            write_clob_to_file(p_directory, l_file_name, l_xml_document);
        END LOOP;
        l_file_name := substr( p_document , instr( p_document , '/' , -1  ) + 1) || '.sh';
        write_clob_to_file(p_directory, l_file_name, l_mapping);
        dbms_lob.freetemporary(l_mapping);
    END export_files;

END fuma_jdr_util;
/
SET DEFINE OFF;
SET SERVEROUTPUT ON;

CREATE OR REPLACE DIRECTORY FUMA_DIR AS '/u01/common/general/ERPMPADEV/files/fuma';
/
GRANT READ, WRITE ON DIRECTORY FUMA_DIR TO apps;
/
select * from dba_directories where directory_name like 'FUMA%';

/


DECLARE
    p_document  VARCHAR2(200);
    p_directory VARCHAR2(200);
BEGIN
    fuma_jdr_util.export_files(
        p_document  => q'[/xxsfc/oracle/apps/per/staff/exit]'
      , p_directory => 'FUMA_DIR'
    );
END;
/