@echo off
title Setting up Fuma

set fuma_env=FUMA_DIRECTORY
set jdev_env=JDEV_USER_HOME
set fuma_dir="%cd%"
set env_db_user=APPS

if not defined %fuma_env% (
    setx %fuma_env% %fuma_dir%
    setx FUMA %fuma_dir%\Fuma.py -f
    setx FUMA_SECURE %fuma_dir%\secure\credentials.py
)
echo -------------------------------------------------------------------------
echo setting environment Variables
if defined %fuma_env% ( echo %fuma_env% : Y ) else ( echo %fuma_env% : N )
if defined %jdev_env% ( echo %jdev_env% : Y ) else ( echo %jdev_env% : N )
echo -----------------------------------------------------------------------
echo installing dependencies
color ce
echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
pip install -r %fuma_dir%\_others\requirements.txt
echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
color
echo setting up credentials
echo =============================================================================
color b
python %fuma_dir%\secure\credentials.py -a set 
color 
echo =============================================================================
@rem echo running tests
@rem python %fuma_dir%\Fuma.py -f %fuma_dir%\_others\db_objects.yml
@rem echo deleting temp files
@rem rmdir %fuma_dir%\_builds /s /q

pause
