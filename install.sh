#!/bin/bash

# Color Definitions
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly GREEN='\033[32m'
readonly PURPLE='\033[36m'
readonly RESET='\033[0m'

# Function to print INFO messages
log_info() {
    echo -e "${YELLOW}[INFO] $1${RESET}"
}

# Function to print SUCCESS messages
log_success() {
    echo -e "${GREEN}[SUCCESS] $1${RESET}"
}

# Function to print ERROR messages
log_error() {
    echo -e "${RED}[ERROR] $1${RESET}"
}

# Function to print WARNING messages
log_warning() {
    echo -e "${PURPLE}[WARNING] $1${RESET}"
}

check_dependencies() {
    for cmd in curl sed yq btrfs; do
        if ! command -v $cmd &>/dev/null; then
            log_error "$cmd is not installed. Please install it and try again."
            return 1
        fi
    done
    return 0
}

main() {
    1. Ver si estan installados todos dependecias necesarios
        1.1 Si no estan installados
            1.1.1 Preguntar a usuario si los quero instalar sino abortar proceso
            1.1.2 Instalar cada dependecia
    2. Ver si ya tiene config.yaml
        2.1 Preguntar al usuario la ruta a cada disco para backup
        2.2 Crear fichero config.yaml
        2.3 Escribir neuvas rutas al este fichero
    3. Ver si discos estan montado
        3.1 Si no estan montados, montarlos
        3.2 Si no se puede montar, abortar proceso
    4. Verificar la estructura de carpetas en cada disco
        4.1 Si no hay, crear carpeta <path>/${HOSTNAME}
        4.2 Si no hay, crear <path>/${HOSTNAME}/data con `btrfs subvolume create`
        4.3 Si no hay, crear <path>/${HOSTNAME}/snapshots/{daily,weekly,monthly}
    5. Si no tiene configurada la politica de rotacion
        5.1 Preguntarla y escrbirla en fichero de configuracion
    6. Si no tiene configurada backup de cada base de datos de Postgresql
        6.1 Preguntarla y escrbirla en fichero de configuracion
    7. Si no tiene configurado las rutas para hacer backup
        7.1 En caso que no lo tiene, preguntar la ruta
        7.2 Si esta ruta correponde al algun servicio, entonces nombre de este servicio de systemmd
        7.3 Escribir en fichero de configuracion
    8. Si no tiene configurado hacer backup de /etc
        8.1 Preguntarla y escrbirla en fichero de configuracion
    9. Si no tiene configurado backup de docker
        9.1 Preguntarla y escrbirla en fichero de configuracion
    10. Si no tiene configurado backup de certificados
        10.1 Preguntarla y escrbirla en fichero de configuracion
    10a: Si no tiene confgirado notificaiones por Telegram
        10a.1 Preguntarla y escrbirla en fichero de configuracion
        10a.2 Si es positivo, preguntar sobre bot key
        10b.3 Crear fichero .env con bot key
    11. Una vez pasado mostrar el resultado de confg.yaml
    12. Logs de backup script
        12.1 Crear fichero para logs backup_<hostname>.log
        12.2 Crear fichero de logrotate
    13. Crear timer
        13.1 Crear service
        13.2 Preguntar la exprecion cron y crear timer
        13.3 Enable timer
    14. Preguntar si usuario quere hacer backup ahora
        14.1 En caso que si hacer backup
    15. Desmontar las particiones
}

main
