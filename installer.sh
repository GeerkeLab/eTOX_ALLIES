#!/usr/bin/env bash

# eTOXLIE installer script
# version 1.0
# Author: Marc van Dijk, VU University Amsterdam
# August 2016

# Get root directory of script
pushd `dirname $0` > /dev/null
ROOTDIR=`pwd -P`
popd > /dev/null

# CLI variables
SETUP=0
UPDATE=0
TEST=0
FORCE=0
PYTHON='python2.7'
VENVTOOL=
NO_VENV=0
USE_CONDA=0

# Internal variables
_PYTHON_PATH=
_PYV=
_PY_SUPPORTED=( 2\.7\* )
_PY_PACKAGES=( )
_PY_VENV=
_PY_VENV_ACTIVE=0
_VENVPATH=${ROOTDIR}/etox_venv

# Sed the right version of sed for multi-platform use.
SED=$( which gsed )
[ ! -n "$SED" ] && SED=$( which sed )

USAGE="""eTOXlie setup script

This script installes or updates the eTOXlie 
software on your system.

Main options:
-s|--setup:         Install LIE Software package.
-u|--update:        Update LIE Software package.
            
Subroutines:
-f|--force:         Force reinstall or update.
                    Default: $FORCE

Installation/update variables:
-p|--python:        Python version to use.
                    Default = $PYTHON
-e|--venv:          Python virtual environment tools to use.
                    Currently the Python 2.x virtualenv
-l|--local-dev      Installs lie studio components inplace, making the easily editable.
-n|--no-venv        Do not use a virtual environment but system installed python packages
-c|--conda          Setup virtual environment using conda/miniconda

-h|--help:          This help message
"""

# Command line argument handling
for i in "$@"; do
    case $i in
        -h|--help)
        echo "$USAGE"
        exit 0
        shift # past argument with no value
        ;;
        -f|--force)
        FORCE=1
        shift # past argument with no value
        ;;
        -s|--setup)
        SETUP=1
        shift # past argument with no value
        ;;
        -u|--update)
        UPDATE=1
        shift # past argument with no value
        ;;
        -p=*|--python=*)
        PYTHON="${i#*=}"
        shift # past argument=value
        ;;
        -e=*|--venv=*)
        VENVTOOL="${i#*=}"
        shift # past argument=value
        ;;
        -l|--local-dev)
        LOCALDEV=1
        shift # past argument with no value
        ;;
        -n|--no-venv)
        NO_VENV=1
        shift # past argument with no value
        ;;
        -c|--conda)
        USE_CONDA=1
        shift # past argument with no value
        ;;
        *)
        echo "$USAGE"
        exit 0 # unknown option
        ;;
    esac
done

# Check if array contains element
function containsElement () {
    local e
    for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}

# Check if string is a valid path
# - actual path should contain at least one forward slash
# - path should exists
# - optionally check if file is executable
function _is_valid_path () {
    
    local FILE_TYPE=${2:-f}
    local IS_PATH=1
    [[ $( grep -o '/' <<<  $1 | wc -l ) -ne 0 ]] && $IS_PATH=0
    
    if [[ "$FILE_TYPE" == "-x" ]]; then
        if [[ $IS_PATH && -x $1 ]]; then
        return 0
        fi
    else
        if [[ $IS_PATH && -f $1 ]]; then
        return 0
        fi
    fi
    
    [[ $IS_PATH -eq 0 ]] && echo "ERROR: $1 seems to be a path but it is not valid"
    return 1
}

# Check Python version
# - Check for prefered version, default $PYTHON
# - Check CLI defined python path or name
# - Check python version in users path
function _resolve_python_version () {
  
    # Check if $PYTHON is a known executable by name
    # else check if it is a valid path and is executable.
    _PYTHON_PATH=$( which ${PYTHON##*/} )
    if [[ -z $_PYTHON_PATH ]]; then 
        if _is_valid_path $PYTHON '-x'; then
        _PYTHON_PATH=$PYTHON
        else
        echo "ERROR: Python executable $PYTHON could not be resolved"
        exit 1
        fi
    fi
    echo "INFO: Python executable $PYTHON resolved to $_PYTHON_PATH"
    
    # Check if _PYTHON_PATH is actually Python.
    local IS_PYTHON="$( $_PYTHON_PATH --version 2>&1 | head -1 | awk '{print tolower($1)}' )"
    if [[ "$IS_PYTHON" != "python" ]]; then
        echo "ERROR: Executable does not seem to be python, $_PYTHON_PATH" 
        exit 1
    fi
    
    # Check if the python version is supported
    local SUPPORT_PYV=1
    if [[ "$IS_PYTHON" == "python" ]]; then
        
        _PYV=$( $_PYTHON_PATH --version 2>&1 | head -1 | awk '{print $2}')
        for pyv in "${_PY_SUPPORTED[@]}"; do
        if [[ $_PYV == $pyv ]]; then
            echo "INFO: Python version $_PYV supported"
            SUPPORT_PYV=0
            break
        fi
        done
        
    fi
    
    if [[ $SUPPORT_PYV -eq 1 ]]; then
        echo "ERROR: eTOXlie supports python version: "${_PY_SUPPORTED[@]}". Found: $_PYV"
        echo "ERROR: If you have one of the supported Python versions installed, supply the path using the -p/--python argument"
        exit 1
    fi
    
    echo "INFO: Using Python version $_PYV at $_PYTHON_PATH"
    return 0
}

# Check Python virtual environment options
# - If python version 3, use standard lib venv module
# - If python version 2.x then check if virtualenv is installed
function _resolve_python_venv () {
  
    # Python 3.4 or larger, use buildin venv module  
    if [[ $_PYV == 3\.* ]]; then
        echo "INFO: Using Python version $_PYV Virtual environment module (venv) part of standard library"
        _PY_VENV="$_PYTHON_PATH -m venv"
    
    # Python 2.x look for virtualenv tool
    else
        
        # If user provided path to virtualenv tool (-e/-venv), check
        if [[ -f $VENVTOOL ]]; then
        _PY_VENV="$VENVTOOL -p $_PYTHON_PATH"
        
        else   
          # Look for virtualenv tool that may be named differently
          local _virtualenv
          local _pyv_venv_options=( "virtualenv" "virtualenv-${_PYV%.*}" )
          for pyv_venv in "${_pyv_venv_options[@]}"; do
              _virtualenv=$( which $pyv_venv )
              if [[ ! -z $_virtualenv ]]; then
              break
              fi
          done
        
          if [[ -z $_virtualenv ]]; then
              echo "ERROR: For Python version $_PYV the 'virtualenv' tool is required for installation of eTOXlie dependencies"
              echo "ERROR: It could not be found looking for: "${_pyv_venv_options[@]}" $VENVTOOL"
              echo "ERROR: If you have virtualenv installed, supply the path using the -e/--venv argument or"
              echo "ERROR: Install using 'pip install virtualenv' or similar"
              exit 1
          fi
        
          _PY_VENV="$_virtualenv -p $_PYTHON_PATH"
        fi
    fi
    
    [[ -z $_PY_VENV ]] && echo "ERROR: no Python venv tools defined", exit 1
    
    echo "INFO: Setup Python virtual environment using $_PY_VENV"
    return 0
}

# Check the directory structure
# - Create logs and temporary files directory
# - Change permissions of executables in bin
function _check_dir_structure () {
    
    for path in '/data/logs'; do
        if [ ! -d ${ROOTDIR}$path ]; then
        echo "INFO: Create directory ${ROOTDIR}$path"
        mkdir ${ROOTDIR}$path
        fi
    done
    
    for exe in $( ls ${ROOTDIR}/bin/*.py ${ROOTDIR}/bin/*.sh ) ; do
      chmod +x $exe
    done
    
}

# Try to autodetect essential executables and update settings.json
function _executable_autodetect() {

  # Init settings.json
  if [ ! -e ${ROOTDIR}/data/settings.json ] && [ -e ${ROOTDIR}/data/settings_default.json ]; then
    cp ${ROOTDIR}/data/settings_default.json ${ROOTDIR}/data/settings.json
    echo "INFO: copy settings_default.json to settings.json in ${ROOTDIR}/data directory"
  fi
  
  # Autodetect ACEPYPE
  local _ACPYPE=$( which acpype )
  if [[ ! -z "$_ACPYPE" ]]; then
    echo "INFO: found acpype.py at $_ACPYPE"
    
    $SED "s~\"ACEPYPE.*~\"ACEPYPE\": \"$_ACPYPE\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json 
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
  fi
  
  # Autodetect GROMACS
  local _GMXRC=$( which gmxrc )
  if [[ ! -z "$_GMXRC" ]]; then
    _GROMACS=${_GMXRC%%/bin/gmxrc}
    echo "INFO: found gromacs at $_GROMACS"
    
    $SED "s~\"GMXRC.*~\"GMXRC\": \"$_GMXRC\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json 
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
    
    $SED "s~\"GROMACSHOME.*~\"GROMACSHOME\": \"$_GROMACS\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
  fi
  
  # Autodetect AMBER
  if [[ ! -z "$AMBERHOME" ]]; then
    echo "INFO: found AMBER at $AMBERHOME"
    
    $SED "s~\"AMBERHOME.*~\"AMBERHOME\": \"$AMBERHOME\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
  fi
  
  # Autodetect PLANTS
  local _PLANTS=$( which plants )
  if [[ ! -z "$_PLANTS" ]]; then
    echo "INFO: found plants at $_PLANTS"
    
    $SED "s~\"PLANTS.*~\"PLANTS\": \"$_PLANTS\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
  fi
  
  # Autodetect PARADOCKS
  local _PARADOCKS=$( which paradocks )
  if [[ ! -z "$_PARADOCKS" ]]; then
    echo "INFO: found paradocks at $_PARADOCKS"
    
    $SED "s~\"PARADOCKS.*~\"PARADOCKS\": \"$_PARADOCKS\",~" ${ROOTDIR}/data/settings.json > ${ROOTDIR}/data/temp.json
    \mv ${ROOTDIR}/data/temp.json ${ROOTDIR}/data/settings.json
  fi
}

# Check if virtual environment is installed and activate
function _activate_py_venv () {
    
    if [[ $USE_CONDA -eq 0 ]]; then
    
      if [[ ! -e ${_VENVPATH}'/bin/activate' ]]; then
          echo "ERROR: Python virtual environment not installed (correctly)"
          echo "ERROR: Unable to activate it, not activation script at ${_VENVPATH}/bin/activate"
          exit 1
      fi
    
      if [[ $_PY_VENV_ACTIVE -eq 0 ]]; then
          source ${_VENVPATH}'/bin/activate'
      fi
      
    else
      source activate etox_venv
    fi  
    
    echo "INFO: Activated Python virtual environment"
    _PY_VENV_ACTIVE=1
}

# Setup the Python virtual environment
# - No virtual environment path yet, create it
# - Already there, optionally force reinstall
function _setup_python_venv () {
    
    # Create or upgrade the Python virtual environment
    if [ -d $_VENVPATH ]; then
        
        # Remove and reinstall venv
        if [[ $FORCE -eq 1 ]]; then
          echo "INFO: Reinstall Python virtual environment at ${_VENVPATH}"
          \rm -rf $_VENVPATH
          $_PY_VENV $_VENVPATH
        else
          echo "INFO: Virtual environment present, not reinstalling"
        fi
        
    else
        echo "INFO: Create Python virtual environment"
        $_PY_VENV $_VENVPATH
    fi
    
    return 0
}

# Setup the conda/miniconda managed virtual environment
function _setup_conda_venv () {
    
  local _CONDA=$( which conda )
  if [[ ! -z "$_CONDA" ]]; then
    
    # Create or upgrade the Conda virtual environment
    if [[ ! -z "$( $_CONDA info --envs | grep etox_venv )" ]]; then
        
        # Remove and reinstall venv
        if [[ $FORCE -eq 1 ]]; then
          echo "INFO: Reinstall Conda virtual environment"
          $_CONDA remove --name etox_venv --all
          $_CONDA create --name etox_venv
        else
          echo "INFO: Virtual environment present, not reinstalling"
        fi
        
    else
      echo "INFO: Create conda/miniconda managed virtual environmentnames 'etox_venv'"
      $_CONDA create --name etox_venv
    fi
    
  else
    echo "ERROR: conda executable not found. Unable to install virtual environment"
    exit 1
  fi
  
  return 0
}

# Install python packages in virtual environment
function _install_update_packages () {
        
    # Activate venv
    _activate_py_venv

    # Check if pip is in virtual environment
    PIPPATH=$( which pip )
    if [[ -z "$PIPPATH" ]]; then
        echo "ERROR: unable to activate Python virtual environment. pip not found"
        exit 1
    fi
            
    # Update virtual environment
    if [[ $UPDATE -eq 1 ]]; then
        echo "INFO: Update Python virtual environment at $_VENVPATH"
        $PIPPATH freeze --local | grep -v '^\-e' | cut -d = -f 1  | xargs -n1 pip install -U
    else
        $PIPPATH install -r ${ROOTDIR}/Pipfile
    fi
    
    return 0
}

# ========== MAIN ========== 

echo ""
echo "==================== eTOXlie installer script ====================="
echo "Date: $( date )"
echo "User: $( whoami )"
echo "System: $( uname -mpnsr )"
echo "Install dir: $ROOTDIR"
echo "====================================================================="
echo ""

cd $ROOTDIR

# 1) Resolve Python version and virtual env options
if [[ $NO_VENV -eq 0 ]]; then
  _resolve_python_version
  
  # 1.1) Use default Python venv tool or Conda managed virtual environment
  if [[ $USE_CONDA -eq 0 ]]; then
    _resolve_python_venv
  else
    echo "INFO: Use conda/miniconda managed virtual environment"
  fi
  
else
  echo "INFO: Skip setup of Python virtual environment."
  echo "INFO: Python package dependencies should be installed on the system."
fi

# 2) Check directory structure
_check_dir_structure

# 3) Install virtual environment
if [[ $SETUP -eq 1 && $NO_VENV -eq 0 ]]; then
  
  # 3.1) Install Python or conda/miniconda virtual environment
  if [[ $USE_CONDA -eq 0 ]]; then
    _setup_python_venv
  else
    _setup_conda_venv
  fi
fi

# 4) Install/update python packages
if [[ $NO_VENV -eq 0 ]]; then
  if [[ $SETUP -eq 1 || $UPDATE -eq 1 ]]; then
      _install_update_packages
  fi
fi

# 5) Autodetect essential third-party executables
_executable_autodetect

# Deactivate Python venv
if [[ $USE_CONDA -eq 0 ]]; then
  deactivate >/dev/null 2>&1
else
  source deactivate
fi

# Finish
echo "NOTE: eTOXlie installation succesful"
exit 0
