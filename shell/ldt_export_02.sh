#!/usr/bin/env bash
#| -- ----------------------------------------------------- -- | 
#| -- Oracle Application Objects Deployment Script          -- |
#| -- Author   : Daniel Kibetu <dankibetu.cs@gmail.com>     -- |
#| -- Version  : 2.1.6 [08-MARCH-2019]                      -- |
#| -- Revision :               comments                     -- |
#|  *- Added login credentials verification                 ---|
#| -- ---------------------------------------------------- --- |

username="apps";
pass="swara321"
out_dir="";
# 

# -------------------[ Console colours ] -----------------------

Red='\033[0;31m';          # Red
Green='\033[0;32m';        # Green
NC='\033[0m';              # No color
Blue='\033[0;34m';         # Blue
Yellow='\033[0;33m';       # Yellow


if [ -z "$out_dir" ]; then
    ldt_dir=$(pwd);
else
    case $out_dir in
        /*) ldt_dir="${out_dir}" ;;
        *)  ldt_dir=$(pwd)"/${out_dir}";;
    esac
fi

logpath="${ldt_dir}/log";

mkdir -p "${logpath}";
chmod -R 755 "${logpath}";

# check if password is set

if [ -z "${pass}" ]; then
    printf "%b" "${Green}Enter ${username} : ${NC}";
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

if [ -z "${instance}" ];
  then 
    printf "%b" "${Red}Could not establish database connection. Check your login details. \nExiting... ${NC}";
    printf "\n";
    exit 1;
  else
    environment=$instance;
    printf "%b" "${Green}Connection Established : [${environment}] ${NC}";
    printf "\n";
    
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

echo "${tns_entry}"


if [ -z "${APPL_TOP}" ]; then
  printf "%b \n" "${Red}Please execute ${environment} Environment Variable. Exiting...${NC}";
  printf "\n";
	exit 1;
fi

export tns_entry;
export environment;

export ldt_dir;
export logpath;

export username;
export pass;

export Red;
export Green;
export NC;
export Blue;
export Yellow;