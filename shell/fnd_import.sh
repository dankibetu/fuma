#!/usr/bin/env bash
#| -- ----------------------------------------------------- -- | 
#| -- Oracle Application Objects Deployment Script          -- |
#| -- Author   : Daniel Kibetu <danielkibetu@gmail.com>     -- |
#| -- Version  : 3.1.6 [10-DEC-2023]                        -- |
#| -- Revision :               comments                     -- |
#| -- ----------------------------------------------------- -- |

#|  *- Added login credentials verification
#|  *- Added LDT source folder specification
#|  *- Added Instance resolution at runtime 30-SEP-2020
#|  *- Added Support for archive files
#|      bash fnd_import.sh [-s|--source] path
#|          [accepts absolute and relative paths]
#| -- ---------------------------------------------------- --- |

Red='\033[0;31m';          # Red
Green='\033[0;32m';        # Green
NC='\033[0m';              # No color
Blue='\033[0;36m';         # Blue
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

# for path in "${paths[@]}"; do
#   mkdir -p "${path}";
#   chmod 755 "${path}";
#   echo -e "${Green}";
#   ls -ld "${path}";
#   echo -e "${NC}";
# done

#  case "${usr}" in
#    # oraappl|oraprep)
#    #   environment="ERP PREP";
#    #   pass="swar148";
#    # ;;
#    oradat*)
#      environment="ERP DATA";
#      pass="Swara321";
#    ;;
#    oradev)
#      environment="ERP DEV";
#      pass="swara321";
#    ;;
#     applprod)
#      environment="ERP PROD";
#      pass="";
#    ;;
#    *)
#      environment="${DK_AU_ENV}";
#      pass="${DK_AU_PASS}";
#    ;;
#  esac

environment="${DK_AU_ENV}";
pass="${DK_AU_PASS}"
username="apps";
app="XXSFC";

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

export pass; # to prevent multiple password requests. 

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
# check if environment is captured

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
  # Adding support for archive files

  if [[ $ldt_path == *.zip || $ldt_path == *.tar.gz ]]; then

    src_file=$(basename "${ldt_path}");
    src_file="${src_file%.*}";
    temp_source=$(dirname "${ldt_path}")"/${src_file}_src";

    if [ ! -d "${temp_source}" ]; then
      rm -rf "${temp_source}";
    fi

    mkdir -p $temp_source;

    if [[ $ldt_path == *.zip ]]; then
      unzip -q -o $ldt_path -d $temp_source;
    else
      cd "${temp_source}";
      tar xf "${ldt_path}";
    fi

    ldt_path="${temp_source}";
    sql_path="${ldt_path}/sql";
    srs_path="${ldt_path}/srs";
    

    # echo "log_path : ${logpath}";
    # echo "ldt_path : ${ldt_path}";

    # exit 1 
  fi
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
# else
#   mkdir -p $logpath;
#   # logpath=$(pwd)"/${logpath}";
   
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


if [ -z "$affirm" ]; then
  printf "%b" "${Yellow} \nEverything checks out, Do you want to proceed with the Deployment? [Y/N] :  ${NC}";
  read affirm;
else
  printf "%b" "${Yellow} \nEverything checks out, Do you want to proceed with the Deployment? [Y/N] :${NC} ${affirm} \n\n";
fi


if [[ "${affirm,,}" != "y" ]] ; then
    printf "%b \n" "${Red}Deployment Cancelled. Exiting ...${NC}";
    printf "\n";
    printf "\n";

    if [ -d "${temp_source}" ]; then
      rm -rf "${temp_source}";
    fi

    exit 1;
fi

# mkdir -p "${logpath}";

cd $ldt_path;

rm  -f -r "${logpath}/"*.log;

function parseResult(){
  pSearch='(L[0-9]+.log)';
  [[ "${1}" =~ $pSearch ]];
  log=${BASH_REMATCH[1]};

  src=$(pwd)"/${log}";
  pfile=$(basename "${2}");
  dst="${logpath}/${pfile}.u.log";
  lf=$(basename "${dst}");

	mv "${src}" "${dst}";
	echo -e "${Blue}[COMPLETE]${NC} : ${Green}log file : ${lf}${NC}";
}

function sql_script(){
echo -e "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
sqlfile=$(basename "${1}");
echo -e "${Yellow}Executing : ${Green}${sqlfile}${NC} \n";
res=$(sqlplus -s ${username}/${pass}@${tns_entry} << EOF
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
echo -e "${res}\n\n";
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
        xdol=$(echo $f | sed 's/@#/ /g' | tr -s ' ');
        IFS=' ' read -rd '' -a xdo <<<"$xdol";
        nl=$'\n';

        log_file="${xdo[1]}.${xdo[2]}.${xdo[3]}.${xdo[5]}.${xdo[6]}.u.log"
        xdofile="${ldt_path}/${xdo[3]}.${xdo[5]}.${xdo[6]}${xdo[7]}";
        xdofile=${xdofile%$nl};
        # echo "________________________________________________________________________"
        # echo "| file      : ${f}|"
        # echo "| xdofile   : ${xdofile}|";
        # echo "| log_file  : ${log_file}|";
        # echo "________________________________________________________________________"

        res=$(cp -f "${f}" "${xdofile}"  2>&1);
        # echo $res;

        if [ ! -f $xdofile ]; then
          echo -e "${Red}Target file does not exist : '${xdofile}' ${NC}"
          # exit 0;
        fi

        res=$(java oracle.apps.xdo.oa.util.XDOLoader UPLOAD -DB_USERNAME apps -DB_PASSWORD "${pass}" -JDBC_CONNECTION "${tns_entry}" -LOB_TYPE "${xdo[2]}" -LOB_CODE "${xdo[3]}" -XDO_FILE_TYPE "${xdo[4]}" -LANGUAGE "${xdo[5]}" -TERRITORY "${xdo[6]}" -FILE_NAME $xdofile -APPS_SHORT_NAME "${xdo[1]}" -LOG_FILE "${logpath}/${log_file}" -CUSTOM_MODE FORCE 2>&1);
        # echo $res;

        echo -e "${Blue}[COMPLETE]${NC} : ${Green}log file : ${log_file}${NC}";
        rm -f $xdofile;
        result="";
    else
	      lfile=$(basename "${file}");
        if [[ $lfile != *sql*  ]]; then
				  echo -e "${Yellow}[ Skipping File ] ${lfile}${NC}";
        fi
		fi

	    if [[ ! -z "${result}" ]]; then
	      parseResult "${result}" "${file}";
	      result="";
	    fi
	fi
done

# echo "finishing here first"
# exit

for f in `ls $ldt_path | grep DKECP$  | sort -n`; do
  src="${ldt_path}/${f}" ;
  echo "${src}";
done

for f in `ls $ldt_path | grep sql | sort -n`; do
  fn="${ldt_path}/${f}";
  
  if [ -f "$fn" ]; then
    sql_script "${fn}";
  fi
done

# Execute SQL files
if [[ ( -n "${sql_path}" ) && (  -d "${sql_path}" ) ]]; then 
  for f in `ls $sql_path  | sort -n`; do
    fn="${sql_path}/${f}";
    
    if [ -f "$fn" ]; then
      sql_script "${fn}";
    fi
  done
fi


# Deploy SRS Files 
if [[ ( -n "${srs_path}" ) && (  -d "${srs_path}" ) ]]; then 

  echo -e "${Green}Creating SRS Program dependencies${NC}";
  echo -e "${Blue}----------------------------------------------------";

  for f in `ls $srs_path  | sort -n`; do
    fn="${srs_path}/${f}";
    
    if [ -f "$fn" ]; then
        #xsrs=$(echo $f | tr '@#' ' ' | tr -s ' ');
        xsrs=$(echo $f | sed 's/@#/ /g' | tr -s ' ');
        IFS=' ' read -rd '' -a srs <<<"$xsrs";
        nl=$'\n';

        srs_top="${srs[0]}";
        srs_type="${srs[1]}";
        srs_file=${srs[2]%$nl};
	
        if [[ $srs_type == HOST ]]; then
          sn="\$${srs_top}/bin/${srs_file}";
          sn1="\$${srs_top}/bin/${srs_file%%.*}";

          sn_e=$(echo "${sn}" | envsubst);
          sn1_e=$(echo "${sn1}" | envsubst);

          cp -v "${fn}" "${sn_e}";
          chmod +x "${sn_e}";
          ln -sfv $FND_TOP/bin/fndcpesr "${sn1_e}";

          # eval "cp -v ${fn} ${sn}";
          # eval "chmod +x ${sn}";
          # eval "ln -sf $FND_TOP/bin/fndcpesr ${sn1}";

        elif [[ $srs_type == RDF ]]; then
          sn="\$${srs_top}/reports/US/${srs_file}";
          sn_e=$(echo "${sn}" | envsubst);
          cp -v "${fn}" "${sn_e}";
          # eval "cp -v ${fn} ${sn}";
        fi

        echo "Migrating ${srs_type} file : ${srs_file}";
    fi
  done
  
  echo -e "----------------------------------------------------${NC}";
  
fi

path_file="${ldt_path}/paths/ctl.dk";
if [[ -f "${path_file}" ]]; then 
  echo -e "${Green}Creating files and directory dependencies ${NC}";
  echo -e "${Blue}----------------------------------------------------";
  chmod +x "${path_file}";
  # echo "Executing final setup  : ${path_file}";
  bash "${path_file}";
  echo -e "----------------------------------------------------${NC}";
fi

# Deploy personalizations
perz_dir="${ldt_path}/customizations";
perz_path="${perz_dir}/ctl.dk";
if [[ -f "${perz_path}" ]]; then 
  echo -e "${Green}Migrating customizations ${NC}";
  export perz_dir;
  export username;
  # export pass;
  export tns_entry;
  export Green;
  export Red; 
  export NC;
  # echo -e "${Blue}----------------------------------------------------";
  chmod +x "${perz_path}";
  # echo "Executing final setup  : ${perz_path}";
  bash "${perz_path}";
  # echo -e "----------------------------------------------------${NC}";
fi

unset pass; 