#!/bin/bash

# Load key
source .env

readonly DATA_FILE="config.yaml"

# Check if API key are set
if [[ -z "$TELEGRAM_BOT_KEY" ]]; then
  echo "ERROR: API key is not set. Exiting."
  exit 1
fi

# Check if DATA_FILE exists
if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: Data file $DATA_FILE not found. Exiting."
  exit 1
fi

# Function to log messages
log() {
  local level=$1 message=$2
  case "$level" in
  DEBUG) syslog_level="debug" ;; INFO) syslog_level="info" ;;
  WARNING) syslog_level="warning" ;; ERROR) syslog_level="err" ;;
  *) syslog_level="notice" ;; # Default level
  esac
  logger -p user.$syslog_level -t brtfs-backup "$message"
}

# Main function
main() {
    i. Cualqueir error si la notificacines son enable, debe ser enviados
    
    1. Montar cada particiones para hacer backups ( se indica su /dev/ y donde se monta )
        1.1 Si no se puede hacer parar backup
    2. Verificar la estrucutura de carpetas en cada disco
        2.1 Si no esta creada, crearlo
    3. Verificar que backup de Postgesql es enable
        3.1 En caso que si hacer backup de cada base de datos
        3.2 En caso que si hacer backup de configuraciones globales
        3.3 Estos backups guardar en carpeta /tmp
        3.4 Copiar estos backups a cada disco
    4. Hacer backup de /etc en cada disco
        4.1 Excluir ficher sensibles
    5. Hacer backup de rutas indicadas en config.yaml
        5.1 Primero para temprolamente cada servicio
        5.2 Hacer backup
        5.3 Arranger todos servicios parados
    6. Hacer backup de los certificados
        6.1 /etc/letsencrypt/
        6.2 /etc/ssl/private/
        6.3 /etc/nginx/ssl/
    7. Hacer backup de los configuraciones de docker
    8. Hacer los snapshots en cada disco
    9. Limpiar los antiguos snapshot segun la politica establecida
    9a. Mandar la notificacion que los backup esta hecho
    10. Desmontar cada particion
}

# Entry point
main
