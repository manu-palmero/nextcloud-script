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
# Variables #
#############
echo -e "\nDesea ingresar manualmente el usuario y la contraseña de la base de datos? (s/N): \c"
read -n 1 -r db_manual
if [[ "$db_manual" =~ ^[sS]$ ]]; then
    echo "Ingrese el nombre de usuario de la base de datos:"
    read -r db_user
    echo "Ingrese la contraseña de la base de datos:"
    read -r db_password
else
    db_user="nextcloud"
    db_password="password"
fi

echo -e "\nDesea ingresar manualmente el usuario y la contraseña del administrador de Nextcloud? (s/N): \c"
read -n 1 -r admin_manual
if [[ "$admin_manual" =~ ^[sS]$ ]]; then
    echo "Ingrese el nombre de usuario del administrador de Nextcloud:"
    read -r admin_user
    echo "Ingrese la contraseña del administrador de Nextcloud:"
    read -r admin_password
else
    admin_user="admin"
    admin_password="password"
fi
# Ruta del archivo de configuración de Nextcloud
config_file="/var/www/html/config/config.php"
# Ruta del archivo de copia de seguridad del archivo de configuración de Nextcloud
backup_config="/var/www/html/config/config.php.backup"
# Cadena a buscar en el archivo de configuración de Nextcloud
cadena_a_buscar="0 => 'localhost',"
# Dirección IP de la máquina
# Nota: Esto aún no maneja múltiples direcciones IP en la misma máquina, pero se puede mejorar en el futuro
ip=$(hostname -I)
# Eliminar todos los espacios de la variable 'ip' y asignar el resultado de nuevo a 'ip'
# Al usar hostname -I, se obtiene una cadena con la dirección IP seguida de un espacio
# Se usa el formato ${variable//buscar/reemplazar} para reemplazar todas las ocurrencias de 'buscar' con 'reemplazar' en 'variable'
# En este caso, 'buscar' es un espacio ' ' y 'reemplazar' es una cadena vacía ''
ip=${ip// /}
linea_a_agregar="    1 => '$ip', // Generado con script de automatización"

##########################
# Comprobar superusuario #
##########################
echo -e "\n----  Comprobando si hay permisos de root...  ----"
if [ "$EUID" -ne 0 ]; then
    echo "El usuario actual no es root"
    echo "Comprobando si se puede obtener permiso de root con sudo..."
    if sudo -v; then
        echo "Hay permiso de root con sudo."
    else
        echo "No hay permiso de root, asegúrese de que el usuario actual tiene los permisos adecuados. Saliendo..."
        exit
    fi
else
    echo "El usuario actual es root."
fi

#########################
# Actualizar el sistema #
#########################
echo -e "\n----  Actualizando los paquetes del sistema...  ----"
if sudo apt update >/dev/null && sudo apt upgrade -y >/dev/null; then
    echo "Paquetes actualizados."
else
    echo "No se puedieron actualizar los paquetes. Saliendo..."
    exit
fi

###############################
# Instalación de dependencias #
###############################
echo -e "\n----  Instalando dependencias...  ----"
if sudo apt install -y apache2 mariadb-server libapache2-mod-php php-bz2 php-gd php-mysql php-curl php-mbstring php-imagick php-zip php-ctype php-curl php-dom php-json php-posix php-bcmath php-xml php-intl php-gmp zip unzip wget >/dev/null; then
    echo "Dependencias instaladas."
else
    echo "No se pudieron instalar las dependencias. Saliendo..."
    exit
fi

#########################################
# Habilitación de los módulos de apache #
#########################################
echo -e "\n----  Habilitando los módulos de Apache...  ----"
if sudo a2enmod rewrite dir mime env headers >/dev/null; then
    echo "Módulos habilitados."
else
    echo "No se pudieron habilitar los módulos. Saliendo..."
    exit
fi
sudo systemctl restart apache2

##########################
# Configuración de MySQL #
##########################
echo -e "\n----  Configurando MySQL para Nextcloud... ----"
if sudo mysql -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password'; CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; GRANT ALL PRIVILEGES ON nextcloud.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;"; then
    echo "MySQL configurado para Nextcloud."
else
    echo "No se pudo configurar MySQL para Nextcloud. Saliendo..."
    exit
fi

#######################
# Descargar Nextcloud #
#######################
cd /var/www || {
    echo "Error al cambiar directorio. Saliendo..."
    exit
}
echo -e "\n----  Descargando Nextcloud...  ----"
if [ -f latest.zip ]; then
    sudo rm -f latest.zip
fi
if sudo wget -q https://download.nextcloud.com/server/releases/latest.zip >/dev/null; then
    echo "Nextcloud descargado."
else
    echo "No se pudo descargar Nextcloud. Saliendo..."
    exit
fi
echo -e "\n----  Descomprimiendo Nextcloud...  ----"
if sudo unzip latest.zip >/dev/null; then
    echo "Nextcloud descomprimido."
    sudo rm -f latest.zip
else
    echo "No se pudo descomprimir Nextcloud. Saliendo..."
    exit
fi
# cd nextcloud || {
#     echo "Error al cambiar directorio. Saliendo..."
#     exit
# }
# sudo mv -- .* * ../
# cd .. || {
#     echo "Error al cambiar directorio. Saliendo..."
#     exit
# }
# sudo rmdir /var/www/html/nextcloud

sudo chown -R www-data:www-data /var/www/nextcloud

cd /var/www/nextcloud || {
    echo "Error al cambiar directorio. Saliendo..."
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
if sudo -u www-data php occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "$db_user" --database-pass "$db_password" --admin-user "$admin_user" --admin-pass "$admin_password" >/dev/null; then
    echo "Nextcloud configurado."
else
    echo "No se pudo configurar Nextcloud. Saliendo..."
    exit
fi

##########################################
# Agregar IP a los dominios de confianza #
##########################################

# Agregar permisos al archivo para evitar problemas
sudo chmod 777 $config_file

# Crear copia de seguridad de las configuraciones originales
sudo cp $config_file $backup_config

# Crear un archivo temporal para realizar las modificaciones
tempfile=$(mktemp)

# Iterar sobre cada línea del archivo
while IFS= read -r linea; do
    # Agrega el contenido de la variable 'linea' al archivo temporal especificado por 'tempfile'.
    echo "$linea" >>"$tempfile"
    # Si la línea contiene la palabra a buscar, añadir la nueva línea debajo
    if [[ "$linea" == *"$cadena_a_buscar"* ]]; then
        echo "$linea_a_agregar" >>"$tempfile"
    fi
done <"$config_file"

# Reemplazar el archivo original con el archivo temporal modificado y eliminar el archivo temporal
sudo mv "$tempfile" "$config_file"
sudo rm -f "$tempfile"

# Conceder permisos adecuados al archivo de configuración, si no se conceden, Nextcloud no funcionará correctamente
sudo chmod 644 $config_file
sudo chown www-data:www-data $config_file

# Reinicar el servicio de Apache para aplicar los cambios
sudo systemctl restart apache2

if sudo systemctl is-active --quiet apache2; then
    if cat $config_file | grep "$ip" >/dev/null; then
        echo "Dirección IP local agregada a los dominios de confianza."
        echo "Nextcloud está instalado y configurado correctamente."
        echo "Puede acceder a Nextcloud en http://$ip/ o http://localhost/."
    else
        echo "No se pudo agregar la IP a los dominios de confianza."
        echo "Nextcloud está instalado y configurado correctamente."
        echo "Puede acceder a Nextcloud en http://localhost/."
        echo "Para acceder a Nextcloud a través de la dirección IP, agregue la dirección IP a la lista de dominios de confianza en el archivo config.php."
    fi
    echo " - El usuario administrador de Nextcloud es '$admin_user'."
    echo " - La contraseña del administrador de Nextcloud es '$admin_password'."
    if [[ ! "$admin_manual" =~ ^[sS]$ ]]; then
        echo "Recuerde cambiar la contraseña del administrador de Nextcloud por una más segura desde la configuración."
    fi
else
    echo "No se pudo reiniciar Apache. Saliendo..."
    exit
fi