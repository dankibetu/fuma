#!/usr/bin/env bash
#| -- ----------------------------------------------------- -- | 
#| -- Oracle Application Objects Deployment Script          -- |
#| -- Author   : Daniel Kibetu <DKibetu@Safaricom.co.ke>    -- |
#| -- Version  : 2.1.6 [08-MARCH-2019]                      -- |
#| -- Revision :               comments                     -- |
#|  *- Added login credentials verification
#|  *- Added LDT source folder specification
#|  *- Added Instance resolution at runtime 30-SEP-2020
#|      bash fnd_import.sh [-s|--source] path
#|          [accepts absolute and relative paths]
#| -- ---------------------------------------------------- --- |

Red='\033[0;31m';          # Red
Green='\033[0;32m';        # Green
NC='\033[0m';              # No color
Blue='\033[0;34m';         # Blue
Yellow='\033[0;33m';       # Yellow

#| -- ---------------------------------------------------- --- |


usage () {
    cat <<HELP_USAGE
    $0 [<-s|--source>] [<-u|--user>] [<-e|--envar>] 
       [<-p|--path>+]  [<-h|--help>] [<-l|--log>]
       [<-q|--sql>]    
    parameters :
    =================================================================
      -s|--source : directory containing LDT file. [default : ./]
      -u|--user   : run as as supplied user. 
      -e|--envar  : environment variable path
      -p|--path   : paths to create
      -h|--help   : print usage
      -l|--log    : log path
      -q|--sql    : SQL Script
HELP_USAGE
 exit 0
}

#| -- ---------------------------------------------------- --- |
while (( "$#" )); do
    case "$1" in
        -s|--source)
            source="${2}";
            shift 2
        ;;
        -u|--user)
            runas="${2}";
            shift 2
        ;;
        -e|--envar)
            envvar="${2}";
            shift 2
        ;;
        -p|--path)
            paths+=("${2}");
            shift 2
        ;;
        -l|--log)
             logpath="${2}";
            shift 2
        ;; 
        -q|--sql)
             sql="${2}";
            shift 2
        ;;
        --) # end argument parsing
            shift
            usage;
            break
        ;;
        *)    # unknown option
            shift # past argument
            usage;
            break;
        ;;
    esac
done

if [ -z "$runas" ]; then
    usr=$(whoami);
else 
    usr="${runas}";
fi

if [ -n  "$envvar" ]; then 
    echo -e "${Green}Setting environment variable '${envvar}'${NC}";
    source "${envvar} run" ;
fi

username="apps";

for path in "${paths[@]}"; do
  mkdir -p "${path}";
  chmod 755 "${path}";
  echo -e "${Green}";
  ls -ld "${path}";
  echo -e "${NC}";
done

 case "${usr}" in
   oraappl|oraprep)
     username="apps"
     environment="ERP PREP";
     pass="swar148";
    #  instance="ERPPREP";
     app="XXSFC";
   ;;
   oradat*)
     username="apps"
     environment="ERP DATA";
     pass="Swara321";
    #  instance="ERPDATA";
     app="XXSFC";
   ;;
   oradev)
     username="apps"
     environment="ERP DEV";
     pass="swaradev148";
    #  instance="ERPDEV";
     app="XXSFC";
   ;;
    applprod)
     username="apps";
     environment="ERP PROD";
     pass="";
    #  instance="ERPPROD6";
     app="XXSFC";
   ;;
   *)
     username="apps";
     environment="?";
     pass="";
    #  instance="";
   ;;
 esac

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
# check if environment is captured
  
if [ -z "${environment}" ]; then
	printf "%b \n" "${Red}Unknown Environment, exiting ...${NC}";
	exit 1;
fi

if [ -z "${APPL_TOP}" ]; then
  printf "%b \n" "${Red}Please execute ${environment} Environment Variable. Exiting...${NC}";
  exit 1;
fi


if [ -z "${source}" ]; then
  ldt_path=$(pwd);
else
  # check if absolute path is provided
  case "${source}" in
    /*)
      ldt_path="${source}"
      ;;
    *)
      ldt_path=$(pwd)"/${source}";
    ;;
  esac
  # check that the path exists
  if [ ! -d "${ldt_path}" ]; then
    printf "%b" "${Red}LDT file source does not exist. Path : ${ldt_path} ${NC}\n";
    exit 1;
  fi
fi

if [ -z "$logpath" ]; then
  if [[ $ldt_path == */ ]]; then
    logpath="${ldt_path}log" ;
  else
    logpath="${ldt_path}/log" ;
  fi
else
  mkdir -p $logpath;
  logpath=$(pwd)"/${logpath}";
fi

if [ ! -e "$logpath" ]; then
		mkdir "${logpath}";
    chmod 755 "${logpath}";
fi


echo -e "${Blue}------------------------------------------------";
echo "    DB SCHEMA      : ${username} " | tr a-z A-Z;
echo "    ENVIRONMENT    : ${environment}";
echo "    LDT DIRECTORY  : ${ldt_path}";
echo "    LOG DIRECTORY  : ${logpath}";
echo -e "------------------------------------------------${NC}";

printf "%b" "${Yellow} \nEverything checks out, Do you want to proceed with the Deployment? [Y/N] :  ${NC}";
read affirm;

if [[ "${affirm,,}" != "y" ]] ;then
    printf "%b \n" "${Red}Deployment Cancelled. Exiting ...${NC}";
    printf "\n";
    printf "\n";
    exit 1;
fi

cd $ldt_path;

rm  -f -r "${ldt_path}/"*.log;

function parseResult(){
  pSearch='(L[0-9]+.log)';
  [[ "${1}" =~ $pSearch ]];
  log=${BASH_REMATCH[1]};

  src=$(pwd)"/${log}";
  pfile=$(basename "${2}");
  dst="${logpath}/${pfile}.I.log";

	mv ${src} ${dst};
	echo -e "${Green}[COMPLETE] : log file : ${pfile}${NC}.I.log";
}

function sql_script(){
echo -e "${Yellow}Executing Script : ${1}${NC}";
res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF
whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit sql.sqlcode rollback
set serveroutput on
set echo off
set autotrace off
set tab off
set wrap off
set feedback off
set linesize 1000
set pagesize 0
set trimspool on
set headsep off
@${1};

EXIT;
EOF
);
echo -e "${Green}Results ${res} ${NC}";
}

for f in `ls $ldt_path | grep "^[0-9]" | grep -v ".log$" | sort -n`; do
	file="${ldt_path}/${f}" ;

	if [[ -f $f ]]; then
		if [[ $f == *FUNC_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afsload.lct  "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *MSG_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afmdmsg.lct  "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == 04_AME_RULE*  ]]; then
			  result=$(FNDLOAD apps/$pass 0 Y UPLOAD $AME_TOP/patch/115/import/amesrulk.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
    elif [[ $f == 01_WF_*  ]]; then
        result=$(WFLOAD apps/"${pass}" 0 Y FORCE "${file}" 2>&1);
    elif [[ $f == 06_RESP_*  ]]; then
      result=$(FNDLOAD apps/$pass 0 Y UPLOAD $FND_TOP/patch/115/import/afscursp.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *LKUP_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" O Y UPLOAD $FND_TOP/patch/115/import/aflvmlu.lct  "${file}" UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *VSET_*  ]] || [[ $f == *03_KFF_* ]] || [[ $f == *03_EIT_* ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afffload.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *05_CP_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afcpprog.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *07_XMLPDD_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $XDO_TOP/patch/115/import/xdotmpl.lct  "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *BNE_LYT_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $BNE_TOP/patch/115/import/bnelay.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *BNE_CMPNT*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $BNE_TOP/patch/115/import/bnecomp.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *MENU_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afsload.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *BNE_INTGR_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $BNE_TOP/patch/115/import/bneintegrator.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afsload.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *08_REQ_SET_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afcprset.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *REQ_GRP_*  ]]; then
			  result=$(FNDLOAD apps/"${pass}" 0 Y UPLOAD $FND_TOP/patch/115/import/afcpreqg.lct "${file}" - WARNING=YES UPLOAD_MODE=REPLACE CUSTOM_MODE=FORCE 2>&1);
		elif [[ $f == *08_XDO_* ]]; then
        xdol=$(echo $f | tr '@#' ' ' | tr -s ' ');
        IFS=' ' read -rd '' -a xdo <<<"$xdol";

        log_file="${xdo[1]}.${xdo[2]}.${xdo[3]}.${xdo[5]}.${xdo[6]}.u.log"
        xdofile="${ldt_path}/${xdo[3]}.${xdo[5]}.${xdo[6]}${xdo[7]}";

        res=$(cp -f $f $xdofile  2>&1);
        # echo $res;

        if [ ! -f $xdofile ]; then
          echo -e "${Red}Target file does not exist : '${xdofile}' ${NC}"
          # exit 0;
        fi

        result=$(java oracle.apps.xdo.oa.util.XDOLoader UPLOAD -DB_USERNAME apps -DB_PASSWORD "${pass}" -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE "${xdo[2]}" -LOB_CODE "${xdo[3]}" -XDO_FILE_TYPE "${xdo[4]}" -LANGUAGE "${xdo[5]}" -TERRITORY "${xdo[6]}" -FILE_NAME $xdofile -APPS_SHORT_NAME "${xdo[1]}" -LOG_FILE "${logpath}/${log_file}" 2>&1);
        rm -f $xdofile;
        # echo $res;

        echo -e "${Green}[COMPLETE] : log file : ${log_file}${NC}";
    else
	      lfile=$(basename "${file}");
				echo -e "${Yellow}[ Skipping File ] ${lfile}${NC}";
		fi

	    if [[ ! -z "${result}" ]]; then
	      parseResult "${result}" "${file}";
	      result="";
	    fi
	fi
done


for f in `ls $ldt_path | grep rdf$  | sort -n`; do
  src="${ldt_path}/${f}" ;
  dest="\${${app}_TOP}/reports/US/${f}";

  eval "yes | cp ${src} ${dest}";
  eval "chmod 775 ${dest}";

  echo -e "${Green}";
    eval "ls -lrt $dest";
  echo -e "${NC}";

done

for f in `ls $ldt_path | grep prog$  | sort -n`; do
  src="${ldt_path}/${f}" ;
  dest="\${${app}_TOP}/bin/${f}";

  eval "yes | cp ${src} ${dest}";
  eval "chmod 755 ${dest}";
  eval "ln -nsf $FND_TOP/bin/fndcpesr ${dest%.*}";

  echo -e "${Green}";
    eval "ls -lrt ${dest%.*}*";
  echo -e "${NC}";
done

for f in `ls $ldt_path | grep sql$  | sort -n`; do
  sql_script "${ldt_path}/${f}";
done
