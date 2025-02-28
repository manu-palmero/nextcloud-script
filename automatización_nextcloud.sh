#!/bin/bash
# Script de automatización de la instalación de Nextcloud en Debian 12
# Este script instala y configura Nextcloud en un servidor Debian 12.
# Se asume que el servidor Debian 12 está recién instalado y no tiene ningún otro software instalado.
# Este script debe ejecutarse con privilegios de superusuario (root).
# El script instala Apache, MariaDB, PHP y otras dependencias necesarias para Nextcloud.
# Luego descarga e instala Nextcloud, configura la base de datos y realiza otras configuraciones necesarias.
# Al final, el script muestra la URL de Nextcloud y las credenciales de administrador.
# Nota: Este script no maneja la configuración de copias de seguridad. Se recomienda configurar copias de seguridad periódicas.

#############
# Funciones #
#############
function agregar_linea {
    # Modo de uso: agregar_linea archivo.txt "cadena a buscar" "línea a agregar"

    # Verificar si se proporcionaron los argumentos correctos
    if [ "$#" -ne 3 ]; then
        echo -e "Error: Se esperaban 3 argumentos, pero se recibieron $#."
        return 1
    else
        local archivo="$1"
        local cadena_a_buscar="$2"
        local linea_a_agregar="$3"
    fi

    # Usar sed para agregar la línea después de la línea que contiene la cadena a buscar
    sudo sed -i "/$cadena_a_buscar/a\\
$linea_a_agregar" "$archivo" | sudo tee -a "$logfile" >/dev/null
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

function descargar_nextcloud {
    echo -e "\n----  Descargando Nextcloud...  ----"
    if sudo wget -q https://download.nextcloud.com/server/releases/latest.zip | sudo tee -a "$logfile" >/dev/null; then
        echo -e "Nextcloud descargado."
    else
        echo -e "No se pudo descargar Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
        exit 1
    fi
}

##################
# Verificaciones #
##################

# Verificar si el script se está ejecutando en Debian 12
if ! grep -q -e "Debian GNU/Linux 12" -e "bookworm" /etc/os-release; then
    if ! grep -q "Debian GNU/Linux" /etc/os-release || [ "$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release)" -lt 12 ]; then
        echo -e "Este script está diseñado para ejecutarse en Debian 12 o posterior. Saliendo..."
        # exit 1
    fi
fi

# Verificar permiso de superusuario
echo -e "\n----  Comprobando si hay permisos de root...  ----"
if [ "$EUID" -ne 0 ]; then
    echo -e "El usuario actual no es root."
    echo -e "Comprobando si se puede obtener permiso de root con sudo..."
    if sudo -v; then
        echo -e "Hay permiso de root con sudo."
    else
        echo -e "No hay permiso de root, asegúrese de que el usuario actual tiene los permisos adecuados. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
        exit 1
    fi
else
    echo -e "El usuario actual es root."
fi

#############
# Variables #
#############

# Archivo de registro
logfile="$(pwd)/nextcloud_automated_install_$(date +'%d-%m-%Y_%H-%M').log"
touch "$logfile"
echo -e "Archivo log generado en $logfile"
# Redirigir toda la salida estándar y de error al archivo de registro y a la consola
exec > >(tee -a "$logfile")

# Contraseña de la base de datos
echo -e "\nDesea ingresar manualmente el usuario y la contraseña de la base de datos? (s/N): \c"
read -n 1 -r db_manual # -n 1 para leer solo un carácter, -r para evitar que se interprete la barra invertida
if [[ "$db_manual" =~ ^[sS]$ ]]; then
    echo
    echo -e "Ingrese el nombre de usuario de la base de datos: \c"
    read -r db_user
    if [ -z "$db_user" ]; then # -x comprueba si la cadena está vacía
        db_user="nextcloud"
        echo -e "Dejó la entrada vacía. Se usará el nombre de usuario predeterminado 'nextcloud'."
    fi
    echo -e "Ingrese la contraseña de la base de datos: \c"
    read -r db_password
    if [ -z "$db_password" ]; then
        db_password="password"
        echo -e "Dejó la entrada vacía. Se usará la contraseña predeterminada 'password'."
    fi
else
    db_user="nextcloud"
    db_password="password"
fi
echo -e "El usuario de la base de datos es $db_user y la contraseña es $db_password."

# Contraseña de administrador de Nextcloud
echo -e "\nDesea ingresar manualmente el usuario y la contraseña del administrador de Nextcloud? (s/N): \c"
read -n 1 -r admin_manual
if [[ "$admin_manual" =~ ^[sS]$ ]]; then
    echo
    echo -e "Ingrese el nombre de usuario del administrador de Nextcloud: \c"
    read -r admin_user
    if [ -z "$admin_user" ]; then # -x comprueba si la cadena está vacía
        admin_user="admin"
        echo -e "Dejó la entrada vacía. Se usará el nombre de usuario predeterminado 'admin'."
    fi
    echo -e "Ingrese la contraseña del administrador de Nextcloud: \c"
    read -r admin_password
    if [ -z "$admin_password" ]; then
        admin_password="password"
        echo -e "Dejó la entrada vacía. Se usará la contraseña predeterminada 'password'."
    fi
else
    admin_user="admin"
    admin_password="password"
fi
echo -e "El usuario administrador para la interfaz web de Nextcloud es $admin_user y la contraseña es $admin_password."

nextcloud_dir="/var/www/nextcloud" # Directorio de Nextcloud

http_port="8080" # Puerto http

https_port="5555" # Puerto https

dominio="$(hostname).local" # Dominio

cert_dir="/etc/ssl/nextcloud" # Directorio en donde se guardarán los certificados

apache_conf_file="nextcloud-ssl.conf"
apache_conf_dir="/etc/apache2/sites-available"
apache_conf="$apache_conf_dir/$apache_conf_file" # Directorio de configuración de Apache

config_file="$nextcloud_dir/config/config.php" # Ruta del archivo de configuración de Nextcloud

backup_config="$nextcloud_dir/config/config.php.backup" # Ruta del archivo de copia de seguridad del archivo de configuración de Nextcloud

cadena_a_buscar="0 => 'localhost'," # Cadena a buscar en el archivo de configuración de Nextcloud

ip=$(hostname -I) # Dirección IP de la máquina
# Nota: Esto aún no maneja múltiples direcciones IP en la misma máquina, pero se puede mejorar en el futuro

ip=${ip// /} # Eliminar todos los espacios de la variable 'ip' y asignar el resultado de nuevo a 'ip'
# Al usar hostname -I, se obtiene una cadena con la dirección IP seguida de un espacio
# Se usa el formato ${variable//buscar/reemplazar} para reemplazar todas las ocurrencias de 'buscar' con 'reemplazar' en 'variable'
# En este caso, 'buscar' es un espacio ' ' y 'reemplazar' es una cadena vacía ''

linea_a_agregar="    2 => '$ip', // Generado con script de automatización"
linea_a_agregar2="    1 => '$dominio', // Generado con script de automatización"

#########################
# Actualizar el sistema #
#########################

echo -e "\n----  Actualizando los paquetes del sistema...  ----"
if sudo apt-get update | sudo tee -a "$logfile" >/dev/null &&
    sudo apt-get upgrade -y | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Paquetes actualizados."
else
    echo -e "No se puedieron actualizar los paquetes. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
fi

###############################
# Instalación de dependencias #
###############################

echo -e "\n----  Instalando dependencias...  ----"
if sudo apt-get install -y apache2 mariadb-server \
    libapache2-mod-php php-bz2 php-gd php-mysql php-curl \
    php-mbstring php-imagick php-zip php-ctype php-curl php-dom php-json php-posix \
    php-bcmath php-xml php-intl php-gmp zip unzip wget openssl coreutils | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Dependencias instaladas."
else
    echo -e "No se pudieron instalar las dependencias. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
fi

#########################################
# Habilitación de los módulos de apache #
#########################################

echo -e "\n----  Habilitando los módulos de Apache...  ----"
if sudo a2enmod rewrite dir mime env headers ssl | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Módulos habilitados."
else
    echo -e "No se pudieron habilitar los módulos. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
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
    echo -e "MySQL configurado para Nextcloud, la base de datos es 'nextcloud', el usuario es '$db_user' y la contraseña '$db_password'."
else
    echo -e "No se pudo configurar MySQL para Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
fi

#######################
# Descargar Nextcloud #
#######################

cd /var/www || {
    echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
}

if [ -f latest.zip ]; then
    sudo rm -f latest.zip
fi
descargar_nextcloud
# FIXME Esto no funciona
# if [ -f latest.zip ]; then
#     echo -e "El archivo de Nextcloud ya existe, a continuación se comprobará si es válido"
#     echo -e "\n----  Verificando la suma de comprobación de Nextcloud...  ----"
#     if sudo wget -q https://download.nextcloud.com/server/releases/latest.zip.sha256 | sudo tee -a "$logfile" >/dev/null; then
#         echo -e "Suma de comprobación descargada."
#         if sha256sum -c latest.zip.sha256 | sudo tee -a "$logfile" >/dev/null; then
#             echo -e "La suma de comprobación es válida. No hace falta descargar otra vez Nextcloud."
#         else
#             echo -e "La suma de comprobación no es válida. Se descargará Nextcloud desde cero." >&2
#             sudo rm -f latest.zip latest.zip.sha256
#             descargar_nextcloud
#         fi
#     else
#         echo -e "No se pudo descargar la suma de comprobación. Se decargará Nextcloud desde cero." >&2
#         sudo rm -f latest.zip
#     fi
# else
#     descargar_nextcloud
# fi

echo -e "\n----  Descomprimiendo Nextcloud...  ----"
if sudo unzip latest.zip | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Nextcloud descomprimido."
    sudo rm -f latest.zip
else
    echo -e "No se pudo descomprimir Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
fi

sudo chown -R www-data:www-data /var/www/nextcloud

cd $nextcloud_dir || {
    echo -e "Error al cambiar directorio. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
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
    --database-user "$db_user" --database-pass "$db_password" --admin-user "$admin_user" --admin-pass "$admin_password" | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Nextcloud configurado."
else
    echo -e "No se pudo configurar Nextcloud. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
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

sudo mkdir -p "$cert_dir"

# Pedir información al usuario
echo -e "Introduce los datos para el certificado SSL. Deja en blanco para usar valores genéricos."

prompt PAIS "Código de país (C)" "XX"
prompt ESTADO "Estado/Provincia (ST)" "UnknownState"
prompt CIUDAD "Ciudad/Localidad (L)" "UnknownCity"
prompt ORG "Organización (O)" "AnonymousOrg"
prompt UO "Unidad organizativa (OU)" "IT"
# prompt NC "Dominio o IP" "$dominio" # Aún no se usa
# TODO Aquí se puede usar la entrada para el dominio en caso de que se use fuera del ámbito local, en tal caso, la configuración de los dominios de confianza debería estar luego de este apartado y usar la variable NC en lugar de dominio

# Mostrar los valores elegidos
echo -e "Generando certificado con los siguientes datos:"
echo -e "C=$PAIS, ST=$ESTADO, L=$CIUDAD, O=$ORG, OU=$UO"

# Generar certificado autofirmado
if sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$cert_dir/nextcloud.key" -out "$cert_dir/nextcloud.crt" -subj "/C=$PAIS/ST=$ESTADO/L=$CIUDAD/O=$ORG/OU=$UO/CN=$dominio" | sudo tee -a "$logfile" >/dev/null; then
    # C = Código del país (ejemplo: AR para Argentina, US para Estados Unidos).
    # ST = Estado o provincia.
    # L = Ciudad o localidad.
    # O = Nombre de la organización (se puede poner el nombre personal o el de una empresa).
    # OU = Unidad organizativa (se puede dejar vacío dejarlo vacío o poner algo como "IT").
    # CN = Nombre común, que debe ser el dominio o la IP del servidor.
    echo -e "Certificado generado en $cert_dir"
else
    echo -e "No se pudo generar el certifiscado." >&2
    echo -e "Pruebe generarlo luego usando el comando: \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$cert_dir/nextcloud.key" -out "$cert_dir/nextcloud.crt" -subj ""/C=$PAIS/ST=$ESTADO/L=$CIUDAD/O=$ORG/OU=$UO/CN=$dominio""" >&2
fi

# Borrar configuración de apache en caso de que se cree con el comando de instalación de nextcloud
if [ -f $apache_conf ]; then
    echo -e "Borrando configuración antigua de apache..."
    sudo rm -f $apache_conf
fi
# Deshabilitar la configuración predeterminada de Apache
echo -e "\n----  Deshabilitando la configuración predeterminada de Apache...  ----"
for config in /etc/apache2/sites-available/*; do
    sudo a2dissite "$(basename "$config")" | sudo tee -a "$logfile" >/dev/null
    sudo rm -f "$config"
done

sudo chmod 644 $apache_conf_dir
sudo touch $apache_conf
sudo chmod 644 $apache_conf

# Crear archivo de configuración para Nextcloud
sudo bash -c "cat >'$apache_conf' <<EOF
<VirtualHost *:80>
    ServerName '$ip'
    Redirect permanent / https://$ip:$https_port/
</VirtualHost>

<VirtualHost *:$http_port>
    ServerName '$ip'
    DocumentRoot '$nextcloud_dir'

    Redirect permanent / https://$ip:$https_port/
</VirtualHost>

<VirtualHost *:$https_port>
    ServerName '$ip'
    DocumentRoot '$nextcloud_dir'

    SSLEngine on
    SSLCertificateFile '$cert_dir/nextcloud.crt'
    SSLCertificateKeyFile '$cert_dir/nextcloud.key'

    <Directory '$nextcloud_dir'>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
        Allow from all
        RewriteEngine On

        <IfModule mod_dav.c>
            Dav off
        </IfModule>

        SetEnv HOME $nextcloud_dir
        SetEnv HTTP_HOME $nextcloud_dir
    </Directory>

    Header always set Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload'
</VirtualHost>
EOF"

if [ -f /etc/apache2/ports.conf ]; then
    # Configurar Apache para escuchar en los puertos HTTP y HTTPS especificados
    echo -e "\n----  Configurando Apache para escuchar en los puertos HTTP y HTTPS...  ----"
    sudo sed -i "/Listen 80/ a\Listen $http_port" /etc/apache2/ports.conf
    sudo sed -i "s|Listen 443|Listen $https_port https|" /etc/apache2/ports.conf
else
    sudo touch /etc/apache2/ports.conf
    sudo chmod 644 /etc/apache2/ports.conf
    sudo bash -c "cat >'/etc/apache2/ports.conf' <<EOF
Listen 80
Listen $http_port
Listen $https_port https
EOF"
fi

# Habilitar la configuración de Nextcloud en Apache
echo -e "\n----  Habilitando la configuración de Nextcloud en Apache...  ----"
if sudo a2ensite $apache_conf_file | sudo tee -a "$logfile" >/dev/null; then
    echo -e "Configuración de Nextcloud habilitada en Apache."
    sudo systemctl restart apache2
else
    echo -e "No se pudo habilitar la configuración de Nextcloud en Apache. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2
    exit 1
fi

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
    if cat $config_file | grep -e "$ip" -e "$dominio" | sudo tee -a "$logfile" >/dev/null; then
        echo -e "Dirección IP local agregada a los dominios de confianza."
        echo -e "Nextcloud está instalado y configurado correctamente."
        echo -e "Puede acceder a Nextcloud en http://$ip o http://localhost/."
        # echo -e "Puede acceder a Nextcloud en http://$dominio/, http://$ip o http://localhost/." # Por ahora no va a usarse el dominio
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
    exit 0
else
    echo -e "Apache no funciona. Saliendo... \nRevise el archivo de registro ($logfile) para ver el error en detalle." >&2 >&2
    exit 1
fi
