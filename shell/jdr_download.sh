username="apps";
password="safmpaps24"
tns_entry="${AD_APPS_JDBC_URL}";

function jdr_to_file(){
res=$(sqlplus -s ${username}/${password}@${tns_entry} << EOF
set feedback off
set heading off
set termout off
set linesize 1000
set trimspool on
set verify off

variable l_out_file    varchar2(4000)

exec :l_out_file := '$2';

spool $1

DECLARE
    PROCEDURE print_long_line ( p_text VARCHAR2 ) IS
        v_offset PLS_INTEGER := 1;
        v_chunk  VARCHAR2(255);
    BEGIN
        WHILE v_offset <= length(p_text) LOOP
            v_chunk := substr(p_text, v_offset, 255);
            dbms_output.put(v_chunk);
            v_offset := v_offset + 255;
        END LOOP;
    END;

    PROCEDURE export_document (
        p_path      VARCHAR2
      , p_formatted NUMBER DEFAULT 1
    ) IS
        l_chunk    VARCHAR2(32000);
        l_complete INTEGER;
    BEGIN
        WHILE nvl(l_complete, 0) = 0 LOOP
            l_chunk := jdr_mds_internal.exportdocumentasxml(l_complete, p_path, p_formatted);
            IF l_chunk IS NOT NULL THEN
                print_long_line(l_chunk);
            END IF;
        END LOOP;
        dbms_output.new_line;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END export_document;

BEGIN
	DBMS_OUTPUT.ENABLE(1000000);
    export_document(:l_out_file);
END;
/
EXIT;
EOF
);
}


function jdr_doc(){

res=$(sqlplus -s ${username}/${password}@${tns_entry} << EOF

whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit sql.sqlcode rollback

set serveroutput on
set define off

set echo off

set autotrace off
set tab off
set wrap off
set feedback off
set linesize 1000
set pagesize 0
set trimspool on
set headsep off

variable l_doc_path    varchar2(4000)

exec :l_doc_path      := '$1';

DECLARE
    TYPE lt_string_table IS
        TABLE OF VARCHAR2(32000) INDEX BY PLS_INTEGER;
    l_jdr_paths lt_string_table;

    PROCEDURE print_long_line(p_text VARCHAR2) IS
        v_offset PLS_INTEGER := 1;
        v_chunk VARCHAR2(255);
    BEGIN
        WHILE v_offset <= LENGTH(p_text) LOOP
            v_chunk := SUBSTR(p_text, v_offset, 255);
            DBMS_OUTPUT.PUT_LINE(v_chunk);
            v_offset := v_offset + 255;
        END LOOP;
    END;

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
            --dbms_output.put_line('Printing contents of ' || p_path);
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

BEGIN
    DBMS_OUTPUT.ENABLE(1000000);
    list_contents(:l_doc_path, TRUE, l_jdr_paths);
    FOR indx IN 1..l_jdr_paths.count LOOP
        print_long_line(l_jdr_paths(indx));
    END LOOP;

END;
/
EXIT;
EOF
);

IFS=$'\n' read -rd '' -a pls <<<"${res}";
for p1 in "${pls[@]}"; do
	out_file="${JAVA_TOP}${p1}.xml"
	mkdir -p $(dirname $out_file)
	# jdr_to_file $out_file $p1 
	echo "Generating ${out_file}"
done
}


jdr_doc '/xxsfc/oracle/apps/per/staff/exit'