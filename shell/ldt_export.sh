#!/usr/bin/env bash
#| -- ----------------------------------------------------- -- | 
#| -- Oracle Application Objects Deployment Script          -- |
#| -- Author   : Daniel Kibetu <dankibetu.cs@gmail.com>     -- |
#| -- Version  : 2.2.6 [08-MARCH-2019]                      -- |
#| -- Revision :               comments                     -- |
#|  *- Added login credentials verification                 ---|
#| -- ---------------------------------------------------- --- |

usage () {
    cat <<HELP_USAGE
    $0 <-o|--object> <-n|--name>+ [ <-a|--application> ] 
        [ <-r|--alias> ] [ <-t|--transaction> ] [ <-f|--flavour> ]
        [ <-e|--flexfield> ]
    
    parameters :
    =================================================================
      -o|--object           : AOL Object Type to export
      -n|--name             : AOL Object Name
      -a|--application      : AOL application 
      -r|--alias            : AME Rule Key
      -t|--transaction      : AME Transaction ID
      -f|--flavour          : Program flavour <RDF|HOST>
      -c|--context          : Flexfield Context
      -u|--user             : User/Schema
      -e|--flexfield        : flexfield Name
      
HELP_USAGE
 exit 0
}

while (( "$#" )); do
    case "$1" in
        -o|--object)
            aols+=("${2^^}");
            shift 2
        ;;
        -n|--name)
            objects+=("${2}");
            shift 2
        ;;
        -a|--application)
            app_short_name="${2}";
            shift 2
        ;;
        -r|--alias)
            alias="${2}";
            shift 2
        ;;
        -u|--user)
            schema_uv="${2}";
            shift 2
        ;;
        -t|--transaction)
            trans="${2}";
            shift 2
        ;;
        -c|--context)
            flex_name="${2}";
            shift 2
        ;;
        -e|--flexfield)
            dff_name="${2}";
            shift 2
        ;;
        -f|--flavour)
            file_flavour="${2}";
            shift 2
        ;;

        --) # end argument parsingn
            shift
            usage;
            break
        ;;
        *)    # unknown option
            shift # past argument
            echo "This option is : ${2}"
            usage;
        ;;
    esac
done

if [ -z "$alias" ]; then
    alias="${object}";
fi


app=$(sqlplus -S ${username}/${pass} << EOF | grep SHORT_NAME | sed 's/SHORT_NAME//;s/[ ]//g'
  set head off
  set feedback off
  set pagesize 5000
  set linesize 30000
  SELECT 'SHORT_NAME', application_short_name FROM fnd_application WHERE application_short_name = trim(upper('$app_short_name'));
  exit
EOF
);

schema=$(sqlplus -S ${username}/${pass} << EOF | grep SCHEMA | sed 's/SCHEMA//;s/[ ]//g'
  set head off
  set feedback off
  set pagesize 5000
  set linesize 30000
  SELECT 'SCHEMA', username FROM SYS.all_users WHERE UPPER(username) = TRIM(UPPER('$schema_uv'));
  exit
EOF
);

app_top=$(sqlplus -S ${username}/${pass} << EOF | grep APP_TOP | sed 's/APP_TOP//;s/[ ]//g'
  set head off
  set feedback off
  set pagesize 5000
  set linesize 30000
  SELECT 'APP_TOP', basepath FROM fnd_application WHERE application_short_name = '$app';
  exit
EOF
);

function xdo_lob(){
sep="@#";
res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF
whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit sql.sqlcode rollback
set serveroutput on
set echo off
set echo off
set echo off
set autotrace off
set tab off
set wrap off
set feedback off
set linesize 1000
set pagesize 0
set trimspool on
set headsep off

variable l_appl varchar2(200)
variable l_code varchar2(200)
variable l_type varchar2(200)

exec :l_appl        := '$2';
exec :l_code        := '$3';
exec :l_type        := '$4';

DECLARE
    l_file_name     VARCHAR2(1000);
    l_export_name   VARCHAR2(1000);
BEGIN
    SELECT 
        lob_type ||'_' || application_short_name || '_' || lob_code
            || CASE WHEN language = '00' THEN '' ELSE '_' || language END
            || CASE WHEN territory = '00' THEN '' ELSE '_' || territory END
            || substr(file_name, instr(file_name, '.', -1)) 
         AS file_name,
        '08_XDO_${sep}'               ||
            application_short_name    || 
            '${sep}' || lob_type      ||
            '${sep}' || lob_code      ||
            '${sep}' || xdo_file_type ||
            '${sep}' || language      ||
            '${sep}' || territory     ||
            '${sep}' || substr(file_name, instr(file_name, '.', -1)) 
        AS export_name
        INTO l_file_name, l_export_name
     FROM xdo_lobs
    WHERE application_short_name = :l_appl 
        AND lob_code = :l_code
        AND lob_type = :l_type ;

    DBMS_OUTPUT.PUT_LINE(l_file_name);
    DBMS_OUTPUT.PUT_LINE(l_export_name);

EXCEPTION WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE(CHR(0));
END;
/

EXIT;
EOF
);

IFS=$'\n' read -rd '' -a xdo <<<"${res}";
if [ "${#xdo[@]}" -gt 0 ]; then
    mv "${xdo[0]}" "${ldt_dir}/${xdo[1]}";
    echo -e "${Green}[COMPLETE] : file name : ${xdo[0]} ${NC}"; 
else
   echo -e "${Red}[ERROR] : Download Failure : [${4}] ${2}:${3} ${NC}"; 
fi
}

function parseResult(){
    local text="$1"
    local pfile=$(basename "$2")

    # Extract log filename
    local log=$(echo "$text" | awk -F': ' '/Log filename/ {print $2}' | xargs)

    # Extract report filename (not used in mv yet, but available)
    local rpt=$(echo "$text" | awk -F': ' '/Report filename/ {print $2}' | xargs)

    # Validate extracted log filename
    if [[ -z "$log" ]]; then
        echo -e "${Red}[ERROR] : Could not extract log filename from input. Received: '$text'${NC}"
        return 1
    fi

    local src="$(pwd)/$log"
    local dst="${logpath}/${pfile}.E.log"

    # Check file exists
    if [[ ! -f "$src" ]]; then
        echo -e "${Red}[ERROR] : Log file not found: $src${NC}"
        return 1
    fi

    mv "$src" "$dst"
    if [[ $? -ne 0 ]]; then
        echo -e "${Red}[ERROR] : Failed to move $src to $dst${NC}"
        return 1
    fi

    echo -e "${Green}[COMPLETE] Log: $log${NC}"
}

# function parseResult(){
#     echo "${1}";
# 	pSearch='(L[0-9]+.log)';
#     pfile=$(basename "${2}");

#     if [[ ! -f "${1}" ]]; then 
#         echo -e "${Red}[ERROR] : Process '${pfile}' did not generate logs. Please check Application ${NC}"; 
#         return;
#     fi

# 	[[ "${1}" =~ $pSearch ]];
# 	log=${BASH_REMATCH[1]};

# 	src=$(pwd)"/${log}";

#     dst="${logpath}/${pfile}.E.log";

# 	mv ${src} ${dst};
# 	echo -e "${Green}[COMPLETE] : log file : ${pfile}${NC}";
# }

function export_oaf_customization(){
    res=$(java oracle.jrad.tools.xml.exporter.XMLExporter "$1" -username "${username}" -password "${pass}" -dbconnection "${tns_entry}" -rootdir "$2" 2>&1);
    if [[ "${res}" == *"Export completed"* ]]; then
        printf "%b \n" "${Green}${res}${NC}";
        control_file="${2}/ctl.dk";

        if [[ ! -f "${control_file}" ]]; then 
            echo '#!/usr/bin/env bash' > $control_file;
            echo "# Auto Generated on " $(date '+%Y-%m-%d %H:%M:%S') >> $control_file;
            echo "# -------------------------------------------------------------- " >> $control_file;
        fi 

        echo 'file="${perz_dir}'"${1}"'.xml";' >> $control_file;
        echo 'if [[ -f "${file}" ]]; then ' >> $control_file;
        # echo "username='${username}';" >> $control_file;
        echo '  res=$(java oracle.jrad.tools.xml.importer.XMLImporter "${file}" -username "${username}" -password "${pass}" -dbconnection "${tns_entry}" -rootdir "${perz_dir}" 2>&1);' >> $control_file;
        echo '  if [[ "${res}" == *"Import completed"* ]]; then' >> $control_file;
        echo '     printf "%b \n" "${Green}${res}${NC}";' >> $control_file;
        echo '  else' >> $control_file;
        echo '     printf "%b \n" "${Red}${res}${NC}";' >> $control_file;
        echo '     exit 1;' >> $control_file;
        echo '  fi' >> $control_file;
        echo 'else' >> $control_file;
        echo '   printf "%b \n" "${Red}Missing file : ${file}${NC}";' >> $control_file;
        echo 'fi' >> $control_file;
        echo '# -------------------------------------------------------------- ' >> $control_file;
    

    else
        printf "%b \n" "${Red}${res}${NC}";
    fi
# res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF
# set feedback off
# set serveroutput on format wrapped
# set linesize 100
# spool $1
# execute jdr_utils.printDocument('$2', 100);
# spool off
# exit
# EOF
# );    
}


function deploymentLDT(){
    ldt_file="${1}.ldt";
}

function export_plsql(){

res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF

set feedback off
set heading off
set termout off
set linesize 32767
set pagesize 0
set long 1000000
set longchunksize 1000000
set trimspool on
set verify off

variable l_owner        varchar2(10)
variable l_object       varchar2(30)
variable l_file_name    varchar2(100)

exec :l_file_name   := '$1';
exec :l_owner       := '$2';
exec :l_object      := '$3';

spool $1
prompt SET DEFINE OFF
SELECT dbms_metadata.get_ddl('PACKAGE_SPEC', :l_object, :l_owner, '11.2.0') FROM dual;
prompt /
SELECT dbms_metadata.get_ddl('PACKAGE_BODY', :l_object, :l_owner, '11.2.0') FROM dual;
prompt /
prompt SHOW ERRORS
prompt SET DEFINE ON
spool off
set feedback on
set heading on
set termout on
set linesize 100
EXIT;
EOF
 >/dev/null );
}

function export_db_object(){

res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF

set feedback off
set heading off
set termout off
set linesize 32767
set pagesize 0
set long 1000000
set longchunksize 1000000
set trimspool on
set verify off

variable l_owner        varchar2(10)
variable l_object       varchar2(30)
variable l_file_name    varchar2(100)
variable l_object_type  varchar2(30)

exec :l_file_name   := '$1';
exec :l_owner       := '$2';
exec :l_object      := '$3';
exec :l_object_type := '$4';

spool $1
prompt SET DEFINE OFF
SELECT dbms_metadata.get_ddl(:l_object_type, :l_object, :l_owner, '11.2.0') FROM dual;
prompt /
prompt SHOW ERRORS
prompt SET DEFINE ON
spool off
EXIT;
EOF
 >/dev/null );
}

function export_path()
{
    path_var="${1}";
    path_counter="${2}";
    path_dir="${ldt_dir}/paths";
    path_file="${path_dir}/ctl.dk";

    # echo "Exporting Path : ${path_var} ${path_counter}";

    if [[ "${path_counter}" -le 1 ]]; then
        # echo "cleaning up directory ${path_dir}";
        rm -rf "${path_dir}";
        mkdir -p "${path_dir}";
        echo '#!/usr/bin/env bash' > $path_file;
        echo "# Auto Generated on " $(date '+%Y-%m-%d %H:%M:%S') >> $path_file;
        echo "# ------------------------------------------" >> $path_file;
    fi

    
    real_path=$(echo "${path_var}" | envsubst );
    # echo "Real Path : ${real_path}";

    if [[ -f "${real_path}" ]]; then 
        file_name=$(basename "${real_path}");
        # echo "Real Path : ${real_path} basename : ${file_name}";
        
        cp "${real_path}" "${path_dir}/${file_name}";
        echo "# Adding file path sequence ${path_counter}" >> $path_file;
        echo "# --------------------------------------------------------" >> $path_file;

        echo 'file_source=$(dirname "${0}")/'\""${file_name}\";" >> $path_file;
        echo "file_target=\"${path_var}\";" >> $path_file;
        echo 'file_dir=$(dirname "${file_target}");' >> $path_file;
        echo 'mkdir -p "${file_dir}";' >> $path_file;
        echo 'cp -v "${file_source}" "${file_target}";' >> $path_file;

        if [[ -f "${path_dir}/${file_name}" ]]; then
            echo -e "[+]${Green} ${path_var}${NC} File added into the project";
            # path_counter=$((path_counter + 1));
        fi

    elif [[ -d "${real_path}" ]]; then
        echo "# Adding file path sequence ${path_counter}" >> $path_file;
        echo "# --------------------------------------------------------" >> $path_file;
        echo "mkdir -pv \"${path_var}\";"  >> $path_file;
        echo -e "[+]${Green} ${path_var}${NC} Directory added into the project";
        # path_counter=$((path_counter + 1));
    else
        echo -e "[-]${Red}Path ${real_path} is not a valid file or directory${NC}" 
    fi

    # path_counter=$((path_counter+1));
}

function dump_plsql(){
sep=':';
sql_dir="${ldt_dir}/sql";
mkdir -p "${sql_dir}";

res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF

whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit sql.sqlcode rollback

set serveroutput on

set echo off
set echo off
set echo off
set autotrace off
set tab off
set wrap off
set feedback off
set linesize 1000
set pagesize 0
set trimspool on
set headsep off

variable l_seq      number

variable l_owner    varchar2(100)
variable l_object   varchar2(100)
variable l_obj_sep  varchar2(100)
variable l_obj_path varchar2(100)

exec :l_seq      := '$1';
exec :l_owner    := '$2';
exec :l_object   := '$3';
exec :l_obj_sep  := '$sep';
exec :l_obj_path := '$sql_dir';


DECLARE  
    
    CURSOR lc_dependencies ( p_owner VARCHAR2 , p_object VARCHAR2 ) IS
        WITH v_objs AS 
        (
            SELECT
                owner,
                name,
                ROW_NUMBER() OVER( ORDER BY NAME ) AS indx
            FROM
                sys.dba_source
            WHERE
                name LIKE upper(trim(p_object))
                and owner = upper(trim(p_owner))
            GROUP BY owner, name
            ORDER BY name
        ), v_objs2 AS 
        (
            SELECT
                v1.owner,
                v1.name,
                v2.owner    AS dependent_owner,
                v2.name     AS dependent_name,
                ROW_NUMBER() OVER(  ORDER BY v1.indx, v2.indx ) AS indx,
                (
                    SELECT COUNT(1)
                    FROM all_dependencies
                    WHERE referenced_name = v2.name
                        AND name = v1.name
                        AND name != v2.name
                ) AS dependencies
            FROM
                v_objs  v1,
                v_objs  v2
            ORDER BY
                v1.indx,
                v2.indx
        ), v_objs3 AS 
        (
            SELECT
                dependent_owner  AS schema,
                dependent_name   AS package,
                ROW_NUMBER() OVER(PARTITION BY dependent_owner, dependent_name ORDER BY dependencies DESC, indx) AS indx
            FROM
                v_objs2
            ORDER BY
                dependencies DESC,
                indx
        )
        SELECT
            schema,
            package,
            :l_obj_path || lower( '/' || to_char(:l_seq, 'fm00') ||'.'||to_char(rownum, 'fm00')||'.'||schema||'.'||package||'.sql') as file_name
        FROM
            v_objs3
        WHERE
            indx = 1;
            

BEGIN
        
    FOR l_obj IN lc_dependencies(:l_owner, :l_object)
    LOOP
        DBMS_OUTPUT.PUT_LINE(l_obj.schema || :l_obj_sep || l_obj.package || :l_obj_sep || l_obj.file_name || :l_obj_sep||to_char(sysdate, 'DD-MON-YYYY HH24:MI:SS'));
    END LOOP;
    
END;
/
EXIT;
EOF
);
IFS=$'\n' read -rd '' -a pls <<<"${res}";
for p1 in "${pls[@]}"; do
  IFS=$':' read -rd '' -a props <<<"${p1}";
  export_plsql "${props[2]}" "${props[0]}" "${props[1]}";
done
}


# begin execution

 echo -e "${Blue}------------------------------------------------";
 echo "    DB USER          : APPS ";
 echo "    ENVIRONMENT      : ${environment}";
 echo "    APPLICATION      : ${app}";
 echo "    APPLICATION TOP  : ${app_top}";
 echo "    LDT DIRECTORY    : ${ldt_dir}";
 echo "    LOG DIRECTORY    : ${logpath}";
 echo "    SCHEMA/USER      : ${schema}";
 echo -e "------------------------------------------------${NC}";

 programs=();
 
for paol in "${aols[@]}"; do
    for object in "${objects[@]}"; do

         aol=$(echo "$paol" | tr '[:lower:]' '[:upper:]');
         echo  -e "${Blue}   AOL OBJECT    : ${aol} ${NC}";
         echo  -e "${Blue}   OBJECT_NAME   : ${object} ${NC}"

        case "$aol" in
            PROGRAM)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/05_CP_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afcpprog.lct "${out_file}.ldt" PROGRAM APPLICATION_SHORT_NAME="${app}" CONCURRENT_PROGRAM_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}";
                deploymentLDT  "${out_file}";

                prog_type=$(echo "$file_flavour" | tr '[:lower:]' '[:upper:]');
                
                case "$prog_type" in 
                    HOST)
                        programs+=("\$${app_top}/bin/${object}.prog;${app_top};${prog_type}");
                    ;;
                    RDF)
                        programs+=("\$${app_top}/reports/US/${object}.rdf;${app_top};${prog_type}");
                    ;;
                    *)

                    ;;
                esac
            ;;

            AME_RULE)
                tout=$(echo "${alias// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/04_AME_RULE_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $AME_TOP/patch/115/import/amesrulk.lct "${out_file}.ldt" AME_RULES APPLICATION_SHORT_NAME="${app}" TRANSACTION_TYPE_ID="${trans}" RULE_KEY="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            LOOKUP)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_LKUP_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/aflvmlu.lct  "${out_file}.ldt" FND_LOOKUP_TYPE APPLICATION_SHORT_NAME="${app}" LOOKUP_TYPE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            RESPONSIBILITY)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/06_RESP_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afscursp.lct  "${out_file}.ldt" FND_RESPONSIBILITY RESP_KEY="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            WORKFLOW)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_WF_${tout}";
                result=$(WFLOAD apps/$pass 0 Y DOWNLOAD "${out_file}.ldt" "${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            VALUE_SET)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/02_VSET_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" VALUE_SET FLEX_VALUE_SET_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            FORM_PERSONALIZATION)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_FRM_PERZ_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/affrmcus.lct "${out_file}.ldt" FND_FORM_CUSTOM_RULES FORM_NAME="${object}%" 2>&1);
                parseResult "${result}" "${object}"; 
                deploymentLDT  "${out_file}";
            ;;

            MESSAGE)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_MSG_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afmdmsg.lct "${out_file}.ldt" FND_NEW_MESSAGES APPLICATION_SHORT_NAME="${app}" MESSAGE_NAME="${object}%" 2>&1);
                parseResult "${result}" "${object}"; 
                deploymentLDT  "${out_file}";
            ;;

            FUNCTION)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_FUNC_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afsload.lct "${out_file}.ldt" FUNCTION FUNCTION_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            BNE_INTEGRATOR)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/02_BNE_INTGR_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bneintegrator.lct "${out_file}.ldt" BNE_INTEGRATORS INTEGRATOR_ASN="${app}" INTEGRATOR_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
                
                # -- pick all depencies 

                out_file="${ldt_dir}/01_BNE_CMPNT_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnecomp.lct "${out_file}.ldt" BNE_COMPONENTS INTEGRATOR_ASN="${app}" INTEGRATOR_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";

                out_file="${ldt_dir}/03_BNE_LYT_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnelay.lct "${out_file}.ldt" BNE_LAYOUTS INTEGRATOR_ASN="${app}" INTEGRATOR_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}";
                deploymentLDT  "${out_file}"; 
            ;;

            BNE_COMPONENT)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/01_BNE_CMPNT_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnecomp.lct "${out_file}.ldt" BNE_COMPONENTS COMPONENT_ASN="${app}" COMPONENT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            BNE_LAYOUT)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_BNE_LYT_${tout}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnelay.lct "${out_file}.ldt" BNE_LAYOUTS LAYOUT_ASN="${app}" LAYOUT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}";
                deploymentLDT  "${out_file}"; 
            ;;

            MENU)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_MENU_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afsload.lct "${out_file}.ldt" MENU MENU_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            REQUEST_GROUP)
                # out_file="${ldt_dir}/07_REQ_GRP_${object}";
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/07_REQ_GRP_${tout}";
                
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afcpreqg.lct "${out_file}.ldt" REQUEST_GROUP REQUEST_GROUP_NAME="${object}" APPLICATION_SHORT_NAME="${app}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            REQUEST_SET_NAME)
                # out_file="${ldt_dir}/07_REQ_GRP_${object}";
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/08_REQ_SET_${tout}";
                
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afcprset.lct "${out_file}.ldt" REQ_SET REQUEST_SET_NAME="${object}" APPLICATION_SHORT_NAME="${app}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            HR_KFF)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_KFF_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" KEY_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="PER" ID_FLEX_CODE="PEA" ID_FLEX_STRUCTURE_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            HR_EIT)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_EIT_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" DESC_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="PER" DESCRIPTIVE_FLEXFIELD_NAME="Extra Person Info DDF" DESCRIPTIVE_FLEX_CONTEXT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            LOOKUP_DFF)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_EIT_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" DESC_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="FND" DESCRIPTIVE_FLEXFIELD_NAME="FND_COMMON_LOOKUPS" DESCRIPTIVE_FLEX_CONTEXT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            DFF)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_EIT_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" DESC_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="${app}" DESCRIPTIVE_FLEXFIELD_NAME="${dff_name}" DESCRIPTIVE_FLEX_CONTEXT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            PACKAGE)
                dump_plsql "${alias}" "${schema}" "${object}";
            
            ;;

            PERSONALIZATION)
                lpath="customizations";
                perz_dir="${ldt_dir}/${lpath}";
                plocate=$(echo ${object%%$lpath*});
                
                if [[ ${#plocate} -lt ${#object} ]]; then

                    # indx=$(( ${#plocate} + ${#lpath} + 1 ));
                    # suffix=$(echo ${object:$indx});
                    # IFS="\/" read -a pname <<< "${suffix}";
                    # echo "Elements : *${pname[@]}*"

                    mkdir -p "${perz_dir}";
                    # fn=$(basename "${object}")
                    # perz_file="${perz_dir}/${pname[0]}-${pname[1]}-${pname[2]}.xml";
                    # echo "File name : ${perz_file}";
                    # echo "Personalization : ${object}"

                    case "$file_flavour" in 
                        oaf)
                            export_oaf_customization "${object}" "${perz_dir}";     
                        ;;
                        *)
                            echo -e "${Red}${file_flavour} personalization is not currently supported.${NC}";
                        ;;
                    esac
                else
                   echo -e "${Red}${file_flavour} '[${object}]' personalization is not currently supported.${NC}" ;
                fi
                # dump_plsql "${alias}" "${schema}" "${object}";
            
            ;;

            GRANT)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/03_MENU_GNT_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afsload.lct "${out_file}.ldt" GRANT GNT_MENU_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            TEMPLATE)
                lob_type="DATA_TEMPLATE";
                out_prefix="XML_DATDF";
                log_file="${logpath}/${out_prefix}_${object}.e.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            PATH)
                export_path "${object}" "${alias}";
                # ((path_counter=path_counter+1));
                # let "path_counter+=1";
                # echo "Path Counter ${path_counter}"
            ;;

            LAYOUT)
                lob_type="TEMPLATE";
                out_prefix="XML_TMPLT";
                log_file="${logpath}/${out_prefix}_${object}.e.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type  -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
                
                lob_type="TEMPLATE_SOURCE";
                out_prefix="XML_TMPLT_SRC";
                log_file="${logpath}/${out_prefix}_${object}.e.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type  -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            BURSTING)
                lob_type="BURSTING_FILE";
                out_prefix="XML_BRST";
                log_file="${logpath}/${out_prefix}_${object}.e.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            DATA_DEFINITION)
                tout=$(echo "${object// /_}" | tr '[:lower:]' '[:upper:]');
                out_file="${ldt_dir}/07_XMLPDD_${tout}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD  $XDO_TOP/patch/115/import/xdotmpl.lct "${out_file}.ldt"  XDO_DS_DEFINITIONS APPLICATION_SHORT_NAME="${app}" DATA_SOURCE_CODE="${object}" TMPL_APP_SHORT_NAME="${app}" TEMPLATE_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}";

                deploymentLDT  "${out_file}";

            ;;
            *)
                echo -e "${Red}UNSUPPORTED [ OBJECT : ${aol^^} - ${object} ]${NC}";
            ;;
        esac
    done
done

for file in "${programs[@]}"; do
    fp=($(echo $file | tr ";" "\n"));

    sf="${fp[0]}";
    pt="${fp[1]}";
    pd="${fp[2]}";

    df=$(basename "${sf}");

    mkdir -p "${ldt_dir}/srs";
    # echo "cp ${sf} ${ldt_dir}/${pt}@#${pd}@#${df}.DKECP";
    cfs=$( echo "${sf}" | envsubst );
    cfd=$( echo "${ldt_dir}/srs/${pt}@#${pd}@#${df}" | envsubst );
    cp "${cfs}" "${cfd}";
    if [[ -f "${cfd}" ]]; then
        echo -e "[+]${Green} ${df}${NC} Added into the project";
    fi
done