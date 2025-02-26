#!/bin/bash
# Script de automatización de la instalación de Nextcloud en Debian 12
# Este script instala y configura Nextcloud en un servidor Debian 12.
# Se asume que el servidor Debian 12 está recién instalado y no tiene ningún otro software instalado.
# Este script debe ejecutarse con privilegios de superusuario (root).
# El script instala Apache, MariaDB, PHP y otras dependencias necesarias para Nextcloud.
# Luego descarga e instala Nextcloud, configura la base de datos y realiza otras configuraciones necesarias.
# Al final, el script muestra la URL de Nextcloud y las credenciales de administrador.
# Nota: Este script no maneja la configuración de SSL/TLS. Se recomienda configurar SSL/TLS para cifrar la conexión.
# Nota: Este script no maneja la configuración de copias de seguridad. Se recomienda configurar copias de seguridad periódicas.

#############
# Funciones #
#############

function agregar_linea() {
    # Modo de uso: agregar_linea archivo.txt "cadena a buscar" "línea a agregar"

    # Verificar si se proporcionaron los argumentos correctos
    if [ "$#" -ne 3 ]; then
        echo -e "Error: Se esperaban 3 argumentos, pero se recibieron $#."
        return 1
    fi

    local archivo="$1"
    local cadena_a_buscar="$2"
    local linea_a_agregar="$3"

    # Crear un archivo temporal para realizar las modificaciones
    tempfile=$(mktemp)

    # Iterar sobre cada línea del archivo
    while IFS= read -r linea; do
        # Agrega el contenido de la variable 'linea' al archivo temporal especificado por 'tempfile'.
        echo -e "$linea" >>"$tempfile"
        # Si la línea contiene la palabra a buscar, añadir la nueva línea debajo
        if [[ "$linea" == *"$cadena_a_buscar"* ]]; then # Cadena a buscar
            echo -e "$linea_a_agregar" >>"$tempfile"       # Línea a agregar
        fi
    done <"$1" # Archivo de entrada

    # Reemplazar el archivo original con el archivo temporal modificado y eliminar el archivo temporal
    sudo mv "$tempfile" "$archivo"
    sudo rm -f "$tempfile"
}

# Función para pedir datos con valor por defecto
function prompt {
    # Modo de uso: prompt variable "Texto de la pregunta" "Valor por defecto"
    # Verificar si se proporcionaron los argumentos correctos
    if [ "$#" -ne 3 ]; then
        echo -e "Error: Se esperaban 3 argumentos, pero se recibieron $#."
        return 1
    fi

    local var_name=$1
    local prompt_text=$2
    local default_value=$3

    read -rp "$prompt_text [$default_value]: " input_value
    if [ -z "$input_value" ]; then
        eval "$var_name=\"$default_value\""
    else
        eval "$var_name=\"$input_value\""
    fi
}

#############
# Variables #
#############

# Archivo de registro
logfile="$(pwd)/nextcloud_automated_install_$(date +'%d-%m-%Y_%H-%M').log"
touch "$logfile"
echo -e "Archivo log generado en $logfile"

# Contraseña de la base de datos
echo -e "\nDesea ingresar manualmente el usuario y la contraseña de la base de datos? (s/N): \c"
read -n 1 -r db_manual
if [[ "$db_manual" =~ ^[sS]$ ]]; then
    echo -e "Ingrese el nombre de usuario de la base de datos:"
    read -r db_user
    echo -e "Ingrese la contraseña de la base de datos:"
    read -r db_password
else
    db_user="nextcloud"
    db_password="password"
fi

# Contraseña de administrador de Nextcloud
echo -e "\nDesea ingresar manualmente el usuario y la contraseña del administrador de Nextcloud? (s/N): \c"
read -n 1 -r admin_manual
if [[ "$admin_manual" =~ ^[sS]$ ]]; then
    echo -e "Ingrese el nombre de usuario del administrador de Nextcloud:"
    read -r admin_user
    echo -e "Ingrese la contraseña del administrador de Nextcloud:"
    read -r admin_password
else
    admin_user="admin"
    admin_password="password"
fi

nextcloud_dir="/var/www/nextcloud" # Directorio de Nextcloud

http_port="8080" # Puerto http

https_port="5555" # Puerto https

dominio="$(hostname).local" # Dominio

cert_dir="/etc/ssl/nextcloud" # Directorio en donde se guardarán los certificados

apache_conf="/etc/apache2/sites-available" # Directorio de configuración de Apache

config_file="$nextcloud_dir/config/config.php" # Ruta del archivo de configuración de Nextcloud

backup_config="/var/www/html/config/config.php.backup" # Ruta del archivo de copia de seguridad del archivo de configuración de Nextcloud

cadena_a_buscar="0 => 'localhost'," # Cadena a buscar en el archivo de configuración de Nextcloud

ip=$(hostname -I) # Dirección IP de la máquina
# Nota: Esto aún no maneja múltiples direcciones IP en la misma máquina, pero se puede mejorar en el futuro

ip=${ip// /} # Eliminar todos los espacios de la variable 'ip' y asignar el resultado de nuevo a 'ip'
# Al usar hostname -I, se obtiene una cadena con la dirección IP seguida de un espacio
# Se usa el formato ${variable//buscar/reemplazar} para reemplazar todas las ocurrencias de 'buscar' con 'reemplazar' en 'variable'
# En este caso, 'buscar' es un espacio ' ' y 'reemplazar' es una cadena vacía ''

linea_a_agregar="    2 => '$ip', // Generado con script de automatización"
linea_a_agregar2="    1 => '$dominio', // Generado con script de automatización"

##########################
# Comprobar superusuario #
##########################

echo -e "\n----  Comprobando si hay permisos de root...  ----"
if [ "$EUID" -ne 0 ]; then
    echo -e "El usuario actual no es root"
    echo -e "Comprobando si se puede obtener permiso de root con sudo..."
    if sudo -v; then
        echo -e "Hay permiso de root con sudo."
    else
        echo -e "No hay permiso de root, asegúrese de que el usuario actual tiene los permisos adecuados. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
        exit
    fi
else
    echo -e "El usuario actual es root."
fi

#########################
# Actualizar el sistema #
#########################

echo -e "\n----  Actualizando los paquetes del sistema...  ----"
if sudo apt update 2>&1 | sudo tee -a "$logfile" && sudo apt upgrade -y 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Paquetes actualizados."
else
    echo -e "No se puedieron actualizar los paquetes. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi

###############################
# Instalación de dependencias #
###############################

echo -e "\n----  Instalando dependencias...  ----"
if sudo apt install -y apache2 mariadb-server \
    libapache2-mod-php php-bz2 php-gd php-mysql php-curl \
    php-mbstring php-imagick php-zip php-ctype php-curl php-dom php-json php-posix \
    php-bcmath php-xml php-intl php-gmp zip unzip wget openssl 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Dependencias instaladas."
else
    echo -e "No se pudieron instalar las dependencias. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi

#########################################
# Habilitación de los módulos de apache #
#########################################

echo -e "\n----  Habilitando los módulos de Apache...  ----"
if sudo a2enmod rewrite dir mime env headers ssl 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Módulos habilitados."
else
    echo -e "No se pudieron habilitar los módulos. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi
sudo systemctl restart apache2

##########################
# Configuración de MySQL #
##########################

echo -e "\n----  Configurando MySQL para Nextcloud... ----"
if sudo mysql -e \
    "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password'; \
        CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; \
        GRANT ALL PRIVILEGES ON nextcloud.* TO '$db_user'@'localhost'; \
        FLUSH PRIVILEGES;"; then
    echo -e "MySQL configurado para Nextcloud."
else
    echo -e "No se pudo configurar MySQL para Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi

#######################
# Descargar Nextcloud #
#######################

cd /var/www || {
    echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
}
echo -e "\n----  Descargando Nextcloud...  ----"
if [ -f latest.zip ]; then
    sudo rm -f latest.zip
fi
if sudo wget -q https://download.nextcloud.com/server/releases/latest.zip 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Nextcloud descargado."
else
    echo -e "No se pudo descargar Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi
echo -e "\n----  Descomprimiendo Nextcloud...  ----"
if sudo unzip latest.zip 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Nextcloud descomprimido."
    sudo rm -f latest.zip
else
    echo -e "No se pudo descomprimir Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi
# cd nextcloud || {
#     echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
#     exit
# }
# sudo mv -- .* * ../
# cd .. || {
#     echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
#     exit
# }
# sudo rmdir /var/www/html/nextcloud

sudo chown -R www-data:www-data /var/www/nextcloud

cd $nextcloud_dir || {
    echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
}

##############################
# Configuración de Nextcloud #
##############################

echo -e "\n----  Configurando Nextcloud...  ----"
# En esta parte se instala y configura Nextcloud usando el comando occ.
# El comando occ (ownCloud Console) es una herramienta de línea de comandos para administrar Nextcloud.
# Permite realizar diversas tareas administrativas como la instalación, configuración, actualización y mantenimiento de Nextcloud.
# Se ejecuta la instalación como el usuario www-data con las credenciales de base de datos y administrador especificadas.
if sudo -u www-data php occ maintenance:install --database "mysql" --database-name "nextcloud" \
    --database-user "$db_user" --database-pass "$db_password" --admin-user "$admin_user" --admin-pass "$admin_password" 2>&1 | sudo tee -a "$logfile"; then
    echo -e "Nextcloud configurado."
else
    echo -e "No se pudo configurar Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle."
    exit
fi

##########################################
# Agregar IP a los dominios de confianza #
##########################################

# Agregar permisos al archivo para evitar problemas
sudo chmod 777 $config_file

# Crear copia de seguridad de las configuraciones originales
sudo cp $config_file $backup_config

agregar_linea $config_file "$cadena_a_buscar" "$linea_a_agregar"
agregar_linea $config_file "$cadena_a_buscar" "$linea_a_agregar2"

# Conceder permisos adecuados al archivo de configuración, si no se conceden, Nextcloud no funcionará correctamente
sudo chmod 644 $config_file
sudo chown www-data:www-data $config_file

# Reinicar el servicio de Apache para aplicar los cambios
sudo systemctl restart apache2

#######################
# Configuración HTTPS #
#######################

mkdir -p "$cert_dir"

# Pedir información al usuario
echo -e "Introduce los datos para el certificado SSL. Deja en blanco para usar valores genéricos."

prompt PAIS "Código de país (C)" "XX"
prompt ESTADO "Estado/Provincia (ST)" "UnknownState"
prompt CIUDAD "Ciudad/Localidad (L)" "UnknownCity"
prompt ORG "Organización (O)" "AnonymousOrg"
prompt UO "Unidad organizativa (OU)" "IT"
prompt NC "Dominio o IP" "$dominio" # Aún no se usa
# TODO Aquí podría haber otra entrada para el dominio en caso de que se use fuera del ámbito local, en tal caso, la configuración de los dominios de confianza debería estar luego de este apartado y usar la variable NC en lugar de dominio

# Mostrar los valores elegidos
echo -e "Generando certificado con los siguientes datos:"
echo -e "C=$PAIS, ST=$ESTADO, L=$CIUDAD, O=$ORG, OU=$UO"

# Generar certificado autofirmado
if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$cert_dir/nextcloud.key" -out "$cert_dir/nextcloud.crt" \
    -subj "/C=$PAIS/ST=$ESTADO/L=$CIUDAD/O=$ORG/OU=$UO/CN=$dominio" 2>&1 | sudo tee -a "$logfile"; then
    # C = Código del país (ejemplo: AR para Argentina, US para Estados Unidos).
    # ST = Estado o provincia.
    # L = Ciudad o localidad.
    # O = Nombre de la organización (se puede poner el nombre personal o el de una empresa).
    # OU = Unidad organizativa (se puede dejar vacío dejarlo vacío o poner algo como "IT").
    # CN = Nombre común, que debe ser el dominio o la IP del servidor.
    echo -e "Certificado generado en $cert_dir"
else
    echo -e "No se pudo generar el certificado."
    echo -e "Pruebe generarlo luego usando el comando: \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$cert_dir/nextcloud.key" -out "$cert_dir/nextcloud.crt" -subj ""/C=$PAIS/ST=$ESTADO/L=$CIUDAD/O=$ORG/OU=$UO/CN=$dominio"""
fi

# Crear archivo de configuración para Nextcloud
cat >"$apache_conf" <<EOF
<VirtualHost *:$http_port>
    ServerName $dominio
    ServerAdmin admin@$dominio
    DocumentRoot "$nextcloud_dir"
    
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:$https_port/\$1 [R=301,L]

    ErrorLog \${APACHE_LOG_DIR}/nextcloud-http-error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud-http-access.log combined
</VirtualHost>

<VirtualHost *:$https_port>
    ServerAdmin admin@$dominio
    DocumentRoot "$nextcloud_dir"

    SSLEngine on
    SSLCertificateFile "$cert_dir/nextcloud.crt"
    SSLCertificateKeyFile "$cert_dir/nextcloud.key"

    <Directory "$nextcloud_dir">
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

    ErrorLog \${APACHE_LOG_DIR}/nextcloud-https-error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud-https-access.log combined
</VirtualHost>
EOF

########################
# Configuración de PHP #
########################

# Para corregir errores dentro de Nextcloud
for php_ini in /etc/php/*/apache2/php.ini; do
    sudo sed -i 's|upload_max_filesize = .*|upload_max_filesize = 1G|' "$php_ini"
    sudo sed -i 's|post_max_size = .*|post_max_size = 1G|' "$php_ini"
    sudo sed -i 's|memory_limit = .*|memory_limit = 768M|' "$php_ini"
    sudo sed -i 's|;opcache.enable=.*|opcache.enable=1|' "$php_ini"
    sudo sed -i 's|;opcache.enable_cli=.*|opcache.enable_cli=1|' "$php_ini"
    sudo sed -i "s|;overwrite.cli.url=.*|overwrite.cli.url=https://$dominio|" "$php_ini"
done
sudo systemctl restart apache2

###########################
# Finalización del script #
###########################

if sudo systemctl is-active --quiet apache2; then
    if cat $config_file | grep -e "$ip" -e "$dominio" 2>&1 | sudo tee -a "$logfile"; then
        echo -e "Dirección IP local agregada a los dominios de confianza."
        echo -e "Nextcloud está instalado y configurado correctamente."
        echo -e "Puede acceder a Nextcloud en http://$dominio/, http://$ip o http://localhost/."
    else
        echo -e "No se pudo agregar la IP a los dominios de confianza." >&2
        echo -e "Nextcloud está instalado y configurado correctamente."
        echo -e "Puede acceder a Nextcloud en http://localhost/."
        echo -e "Para acceder a Nextcloud a través de la dirección IP, agregue la dirección IP a la lista de dominios de confianza en el archivo config.php."
    fi
    echo -e " - El usuario administrador de Nextcloud es '$admin_user'."
    echo -e " - La contraseña del administrador de Nextcloud es '$admin_password'."
    if [[ ! "$admin_manual" =~ ^[sS]$ ]]; then
        echo -e "\nRecuerde cambiar la contraseña del administrador de Nextcloud por una más segura desde la configuración."
    fi
else
    echo -e "Apache no funciona. Saliendo... \nRevise el archivo de registro ($logfile)para ver el error en detalle." >&2
    exit
fi
