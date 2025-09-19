#!/usr/bin/env bash
#| -- ----------------------------------------------------- -- | 
#| -- Oracle Application Objects Deployment Script          -- |
#| -- Author   : Daniel Kibetu <dankibetu.cs@gmail.com>     -- |
#| -- Version  : 2.1.6 [08-MARCH-2019]                      -- |
#| -- Revision :               comments                     -- |
#|  *- Added login credentials verification                 ---|
#| -- ---------------------------------------------------- --- |
app_art(){
    cat<<APP_ART                                                          
FFFFFFFFFFFFFFFFFFFFFF                                                            
F::::::::::::::::::::F                                                            
F::::::::::::::::::::F                                                            
FF::::::FFFFFFFFF::::F                                                            
  F:::::F       FFFFFFuuuuuu    uuuuuu     mmmmmmm    mmmmmmm     aaaaaaaaaaaaa   
  F:::::F             u::::u    u::::u   mm:::::::m  m:::::::mm   a::::::::::::a  
  F::::::FFFFFFFFFF   u::::u    u::::u  m::::::::::mm::::::::::m  aaaaaaaaa:::::a 
  F:::::::::::::::F   u::::u    u::::u  m::::::::::::::::::::::m           a::::a 
  F:::::::::::::::F   u::::u    u::::u  m:::::mmm::::::mmm:::::m    aaaaaaa:::::a 
  F::::::FFFFFFFFFF   u::::u    u::::u  m::::m   m::::m   m::::m  aa::::::::::::a 
  F:::::F             u::::u    u::::u  m::::m   m::::m   m::::m a::::aaaa::::::a 
  F:::::F             u:::::uuuu:::::u  m::::m   m::::m   m::::ma::::a    a:::::a 
FF:::::::FF           u:::::::::::::::uum::::m   m::::m   m::::ma::::a    a:::::a 
F::::::::FF            u:::::::::::::::um::::m   m::::m   m::::ma:::::aaaa::::::a 
F::::::::FF             uu::::::::uu:::um::::m   m::::m   m::::m a::::::::::aa:::a
FFFFFFFFFFF               uuuuuuuu  uuuummmmmm   mmmmmm   mmmmmm  aaaaaaaaaa  aaaa         

Oracle E-Business Suite R12 Migration Tool
Daniel Kibetu <danielkibetu@gmail.com>
APP_ART
}

app_art;

usage () {
    cat <<HELP_USAGE
    $0 <-o|--object> <-n|--name>+ [ <-a|--application> ] 
        [ <-d|--destination> ] [ <-r|--alias> ] [ <-t|--transaction> ] 
        [ <-e|--environment> ] [ <-u|--user> ] [ <-p|--envar> ] [ <-l|--log> ]
        [ <-f|--flavour> ]
    
    parameters :
    =================================================================
      -o|--object           : AOL Object Type to export
      -n|--name             : AOL Object Name
      -a|--application      : AOL application 
      -d|--destination      : Export Location 
      -r|--alias            : AME Rule Key
      -t|--transaction      : AME Transaction ID
      -e|--environment      : Target Environment <Dev/Prod>
      -u|--user             : Run as user <Used to default credentials>
      -p|--envar            : Location of the Environment Variable <Path>
      -l|--log              : location to place log paths
      -f|--flavour          : Program flavour <RDF|HOST>
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
            app="${2}";
            shift 2
        ;;
        -d|--destination)
            out_dir="${2}";
            shift 2
        ;;
        -r|--alias)
            alias="${2}";
            shift 2
        ;;
        -t|--transaction)
            trans="${2}";
            shift 2
        ;;
        -e|--environment)
            target_env="${2}";
            shift 2
        ;;
        -u|--user)
            runas="${2}";
            shift 2
        ;;
        -p|--envar)
            envvar="${2}";
            shift 2
        ;;
        -l|--log)
            logpath="${2}";
            shift 2
        ;;
        -f|--flavour)
            prog_flavour="${2}";
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

# -------------------[ Console colours ] -----------------------

Red='\033[0;31m';          # Red
Green='\033[0;32m';        # Green
NC='\033[0m';              # No color
Blue='\033[0;34m';         # Blue
Yellow='\033[0;33m';       # Yellow

# --------------[ processing / validations] --------------------

if [ -z "$runas" ]; then
    usr=$(whoami);
else 
    usr="${runas}";
fi

if [ -n  "$envvar" ]; then 
    echo -e "${Green}Setting environment variable '${envvar}'${NC}";
    source "${envvar} run" ;
fi

echo -e "${Yellow}running as : ${usr}${NC}";

if [ -z "$out_dir" ]; then
    ldt_dir=$(pwd);
else

  case $out_dir in
    /*) ldt_dir="${out_dir}" ;;
    *)  ldt_dir="$(pwd)"/${out_dir}"" ;;
  esac

fi




if [ -z "$aols" ]; then
    # echo -e "${Red}Please specify the type of AOL object to export. Use ${Blue}bash fnd_export --object 'object_name' ${NC}";
    usage;
    exit 1;
fi

if [ -z "$objects" ]; then
    # echo -e "${Red}Please specify '${aol}' to export. Use ${Blue}bash fnd_export --object ${aol} --name 'short_name' ${NC}";
    usage;
    exit 1;
fi

owner="";
if [ -z ${target_env} ]; then
    target_env="Dev";
fi

if [[ "${target_env^^}" == *'PROD'* ]]; then
    owner="ORACLE12.1.3";
fi

app=${app^^};
owner_regex='(OWNER[[:blank:]]*=[[:blank:]]*")(.*?)(")';

if [ -z "$alias" ]; then
    alias="${object}";
fi

 case "${usr}" in
   oraappl|oraprep)
     # username="apps"
     environment="ERP PREP";
     pass="swar148";
     # instance="ERPPREP";
     # app="XXSFC";
   ;;
   oradat*)
     # username="apps"
     environment="ERP DATA";
     pass="Swara321";
     # instance="ERPDATA";
     # app="XXSFC";
   ;;
   oradev)
     # username="apps"
     environment="ERP DEV";
     pass="swaradev148";
     # instance="ERPDEV";
     # app="XXSFC";
   ;;
    applprod)
     # username="apps";
     environment="ERP PROD";
     pass="";
     # instance="ERPPROD";
     # app="XXSFC";

   ;; 

   *)
     # username="apps";
     environment="?";
     pass="";
     # instance="";
   ;;
 esac


username="apps";
if [ -z "$app" ]; then
    app="XXSFC";
fi


# check if password is set

if [ -z "${pass}" ]; then
    printf "%b" "${Green}Enter APPS PASSWORD [${environment}] : ${NC}";
    read -s pass;
    printf "\n";

    if [ -z "${pass}" ]; then
      printf "%b \n" "${Red}You did not enter password. Exiting ...${NC}";
      printf "\n";
      printf "\n";
      exit 1;
    fi
fi

# check if password is valid
instance=$(sqlplus -S ${username}/${pass} << EOF | grep INSTANCE | sed 's/INSTANCE//;s/[ ]//g'
  set head off
  set feedback off
  set pagesize 5000
  set linesize 30000
  SELECT 'INSTANCE', applications_system_name FROM fnd_product_groups; 
  exit
EOF
);

# echo 'exit' | sqlplus ${username}/${pass}@${tns_entry} | grep Connected > /dev/null;

if [ -z "${instance}" ];
  then 
    printf "%b" "${Red}Could not establish database connection : [${environment}]. Check your login details. \nExiting... ${NC}";
    printf "\n";
    exit 1;
  else
    printf "%b" "${Green}Connection Established : [${environment}] ${NC}";
    printf "\n";
    environment=$instance;
fi

if [ -z "${AD_APPS_JDBC_URL}" ]; then
  printf "%b" "${Green}Resolving connection using net entry name '${instance}'${NC}\n";

  lsearch='(\(DESC.+\))\s+(OK.+)';
  lres=$(tnsping $instance 2>&1);
  [[ "$lres" =~ $lsearch ]];

  tns_entry=${BASH_REMATCH[1]};
  status=${BASH_REMATCH[2]};

  tns_entry=$(echo -e "${tns_entry}" | tr -d '[:space:]');

  if [[ $lres != *OK* ]]; then
      printf "%b" "${Red}${lres}\nExiting... ${NC}";
      printf "\n";
      exit 1;
  fi

  if [ -z "${environment}" ]; then
    printf "%b \n" "${Red}Unknown Environment, exiting ...${NC}";
    exit 1;
  fi

else
  tns_entry="${AD_APPS_JDBC_URL}";
fi

if [ ! -e "$ldt_dir" ]; then
    mkdir -p $ldt_dir;
    chmod 755 $ldt_dir;
fi

if [ -z "${logpath}" ]; then
    if [[ $ldt_dir == */ ]]; then
        logpath="${ldt_dir}log" ;
    else
        logpath="${ldt_dir}/log" ;
    fi
else
    mkdir -p "${logpath}";
    logpath=$(pwd)"/${logpath}";
fi

if [ ! -e "$logpath" ]; then
    mkdir "${logpath}";
    chmod 755 "${logpath}";
fi


# check if environment is captured
  
if [ -z "${environment}" ]; then
	printf "%b \n" "${Red}Unknown Environment, exiting ...${NC}";
    printf "\n";
	exit 1;
fi

if [ -z "${APPL_TOP}" ]; then
  printf "%b \n" "${Red}Please execute ${environment} Environment Variable. Exiting...${NC}";
  printf "\n";
	exit 1;
fi


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
	pSearch='(L[0-9]+.log)';
	[[ "${1}" =~ $pSearch ]];
	log=${BASH_REMATCH[1]};

	src=$(pwd)"/${log}";
    pfile=$(basename "${2}");
    dst="${logpath}/${pfile}.E.log";

	mv ${src} ${dst};
	echo -e "${Green}[COMPLETE] : log file : ${pfile}${NC}";
}

function deploymentLDT(){
    ldt_file="${1}.ldt"
    if [ ! -z $owner ]; then
        sed -i -r "s/${owner_regex}/\1\\${owner}\\3/g" $ldt_file;
        echo -e "${Green}[COMPLETE] :: Preparing LDT for Production.OWNED BY [${owner}]${NC}";
    fi
}

# begin execution

 echo -e "${Blue}------------------------------------------------";
 echo "    DB USER          : APPS ";
 echo "    ENVIRONMENT      : ${environment}";
 echo "    APPLICATION      : ${app}";
 echo "    LDT DIRECTORY    : ${ldt_dir}";
 echo "    LOG DIRECTORY    : ${logpath}";
 echo -e "------------------------------------------------${NC}";

 programs=();

for paol in "${aols[@]}"; do
    for object in "${objects[@]}"; do

         aol=$(echo "$paol" | tr '[:lower:]' '[:upper:]');
         echo  -e "${Blue}   AOL OBJECT    : ${aol} ${NC}";
         echo  -e "${Blue}   OBJECT_NAME   : ${object} ${NC}"

        case "$aol" in
            PROGRAM)
                out_file="${ldt_dir}/05_CP_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afcpprog.lct "${out_file}.ldt" PROGRAM APPLICATION_SHORT_NAME="${app}" CONCURRENT_PROGRAM_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}";
                deploymentLDT  "${out_file}";
                top="\$${app}_TOP";
                prog_type=$(echo "$prog_flavour" | tr '[:lower:]' '[:upper:]');
                
                case "$prog_type" in 
                    HOST)
                        programs+=("${top}/bin/${object}.prog");
                    ;;
                    RDF)
                        programs+=("${top}/reports/US/${object}.rdf");
                    ;;
                    *)

                    ;;
                esac
            ;;

            AME_RULE)
                out_file="${ldt_dir}/04_AME_RULE_${alias}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $AME_TOP/patch/115/import/amesrulk.lct "${out_file}.ldt" AME_RULES APPLICATION_SHORT_NAME="${app}" TRANSACTION_TYPE_ID="${trans}" RULE_KEY="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            LOOKUP)
                out_file="${ldt_dir}/01_LKUP_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/aflvmlu.lct  "${out_file}.ldt" FND_LOOKUP_TYPE APPLICATION_SHORT_NAME="${app}" LOOKUP_TYPE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            RESPONSIBILITY)
                out_file="${ldt_dir}/06_RESP_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afscursp.lct  "${out_file}.ldt" FND_RESPONSIBILITY RESP_KEY="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            WORKFLOW)
                out_file="${ldt_dir}/01_WF_${object}";
                result=$(WFLOAD apps/$pass 0 Y DOWNLOAD "${out_file}.ldt" "${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            VALUE_SET)
                out_file="${ldt_dir}/02_VSET_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" VALUE_SET FLEX_VALUE_SET_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            MESSAGE)
                out_file="${ldt_dir}/01_MSG_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afmdmsg.lct "${out_file}.ldt" FND_NEW_MESSAGES APPLICATION_SHORT_NAME="${app}" MESSAGE_NAME="${object}%" 2>&1);
                parseResult "${result}" "${object}"; 
                deploymentLDT  "${out_file}";
            ;;

            FUNCTION)
                out_file="${ldt_dir}/01_FUNC_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $FND_TOP/patch/115/import/afsload.lct "${out_file}.ldt" FUNCTION FUNCTION_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            BNE_INTEGRATOR)
                out_file="${ldt_dir}/02_BNE_INTGR_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bneintegrator.lct "${out_file}.ldt" BNE_INTEGRATORS INTEGRATOR_ASN="${app}" INTEGRATOR_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            BNE_COMPONENT)
                out_file="${ldt_dir}/01_BNE_CMPNT_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnecomp.lct "${out_file}.ldt" BNE_COMPONENTS COMPONENT_ASN="${app}" COMPONENT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            BNE_LAYOUT)
                out_file="${ldt_dir}/03_BNE_LYT_${object}";
                result=$(FNDLOAD apps/$pass 0 Y DOWNLOAD $BNE_TOP/patch/115/import/bnelay.lct "${out_file}.ldt" BNE_LAYOUTS LAYOUT_ASN="${app}" LAYOUT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}";
                deploymentLDT  "${out_file}"; 
            ;;

            MENU)
                out_file="${ldt_dir}/03_MENU_${object}";
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
                out_file="${ldt_dir}/03_KFF_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" KEY_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="PER" ID_FLEX_CODE="PEA" ID_FLEX_STRUCTURE_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            HR_EIT)
                out_file="${ldt_dir}/03_EIT_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" DESC_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="PER" DESCRIPTIVE_FLEXFIELD_NAME="Extra Person Info DDF" DESCRIPTIVE_FLEX_CONTEXT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            LOOKUP_DFF)
                out_file="${ldt_dir}/03_EIT_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afffload.lct "${out_file}.ldt" DESC_FLEX P_LEVEL=:"COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL" APPLICATION_SHORT_NAME="FND" DESCRIPTIVE_FLEXFIELD_NAME="FND_COMMON_LOOKUPS" DESCRIPTIVE_FLEX_CONTEXT_CODE="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            
            ;;

            GRANT)
                out_file="${ldt_dir}/03_MENU_GNT_${object}";
                result=$(FNDLOAD apps/$pass O Y DOWNLOAD $FND_TOP/patch/115/import/afsload.lct "${out_file}.ldt" GRANT GNT_MENU_NAME="${object}" 2>&1);
                parseResult "${result}" "${out_file}"; 
                deploymentLDT  "${out_file}";
            ;;

            TEMPLATE)
                lob_type="DATA_TEMPLATE";
                out_prefix="XML_DATDF";
                log_file="${logpath}/${out_prefix}_${object}.D.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            LAYOUT)
                lob_type="TEMPLATE";
                out_prefix="XML_TMPLT";
                log_file="${logpath}/${out_prefix}_${object}.D.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type  -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
                
                lob_type="TEMPLATE_SOURCE";
                out_prefix="XML_TMPLT_SRC";
                log_file="${logpath}/${out_prefix}_${object}.D.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type  -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            BURSTING)
                lob_type="BURSTING_FILE";
                out_prefix="XML_BRST";
                log_file="${logpath}/${out_prefix}_${object}.D.log";
                result=$(java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD -DB_USERNAME apps -DB_PASSWORD $pass -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE $lob_type -LOB_CODE "${object}"  -APPS_SHORT_NAME $app -LANGUAGE en -lct_FILE $XDO_TOP/patch/115/import/xdotmpl.lct  -LOG_FILE $log_file 2>&1);
                xdo_lob "${out_prefix}" "${app}" "${object}" "${lob_type}";
            ;;

            DATA_DEFINITION)
                out_file="${ldt_dir}/07_XMLPDD_${object}";
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

for pn in "${programs[@]}"; do
    eval "cp ${pn} ${ldt_dir}/"
done