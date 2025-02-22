#!/bin/bash

##########################
# Comprobar superusuario #
##########################
echo "----  Comprobando si hay permisos de root...  ----"
if sudo -v; then
    echo "Hay permiso de root."
else
    echo "No hay permiso de root, asegúrese de que el usuario actual tiene los permisos adecuados. Saliendo..."
    exit
fi

#########################
# Actualizar el sistema #
#########################
echo "----  Actualizando los paquetes del sistema...  ----"
if sudo apt update >/dev/null && sudo apt upgrade -y >/dev/null; then
    echo "Paquetes actualizados."
else
    echo "No se puedieron actualizar los paquetes. Saliendo..."
    exit
fi

###############################
# Instalación de dependencias #
###############################
echo "----  Instalando dependencias...  ----"
if sudo apt install -y apache2 mariadb-server libapache2-mod-php php-bz2 php-gd php-mysql php-curl php-mbstring php-imagick php-zip php-ctype php-curl php-dom php-json php-posix php-bcmath php-xml php-intl php-gmp zip unzip wget >/dev/null; then
    echo "Dependencias instaladas."
else
    echo "No se pudieron instalar las dependencias. Saliendo..."
    exit
fi

#########################################
# Habilitación de los módulos de apache #
#########################################
echo "----  Habilitando los módulos de Apache...  ----"
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
echo "----  Configurando MySQL para Nextcloud... ----"
if sudo mysql -e "CREATE USER IF NOT EXISTS 'nextcloud'@'localhost' IDENTIFIED BY 'password'; CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost'; FLUSH PRIVILEGES;"; then
    echo "MySQL configurado para Nextcloud."
else
    echo "No se pudo configurar MySQL para Nextcloud. Saliendo..."
    exit
fi

#######################
# Descargar Nextcloud #
#######################
cd /var/www/html || {
    echo "Error al cambiar directorio. Saliendo..."
    exit
}
echo "----  Descargando Nextcloud...  ----"
if [ -f latest.zip ]; then
    sudo rm -f latest.zip
fi
if sudo wget https://download.nextcloud.com/server/releases/latest.zip >/dev/null; then
    echo "Nextcloud descargado."
else
    echo "No se pudo descargar Nextcloud. Saliendo..."
    exit
fi
echo "----  Descomprimiendo Nextcloud...  ----"
if sudo unzip latest.zip >/dev/null; then
    echo "Nextcloud descomprimido."
    sudo rm -f latest.zip
else
    echo "No se pudo descomprimir Nextcloud. Saliendo..."
    exit
fi
cd nextcloud || {
    echo "Error al cambiar directorio. Saliendo..."
    exit
}
sudo mv -- .* * ../
cd .. || {
    echo "Error al cambiar directorio. Saliendo..."
    exit
}
sudo rmdir /var/www/html/nextcloud

sudo chown -R www-data:www-data /var/www/html

cd /var/www/html || {
    echo "Error al cambiar directorio. Saliendo..."
    exit
}

##############################
# Configuración de Nextcloud #
##############################
echo "----  Configurando Nextcloud...  ----"
# En esta parte se instala y configura Nextcloud usando el comando occ.
# El comando occ (ownCloud Console) es una herramienta de línea de comandos para administrar Nextcloud.
# Permite realizar diversas tareas administrativas como la instalación, configuración, actualización y mantenimiento de Nextcloud.
# Se ejecuta la instalación como el usuario www-data con las credenciales de base de datos y administrador especificadas.
if sudo -u www-data php occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud" --database-pass "password" --admin-user "admin" --admin-pass "password" >/dev/null; then
    echo "Nextcloud configurado."
else
    echo "No se pudo configurar Nextcloud. Saliendo..."
    exit
fi

##########################################
# Correción de los dominios de confianza #
##########################################
config_file="/var/www/html/config/config.php"
backup_config="/var/www/html/config/config.php.backup"
cadena_a_buscar="0 => 'localhost',"
# Nota: Esto aún no maneja múltiples direcciones IP en la misma máquina, pero se puede mejorar en el futuro
ip=$(hostname -I)
# Eliminar todos los espacios de la variable 'ip' y asignar el resultado de nuevo a 'ip'
# Al usar hostname -I, se obtiene una cadena con la dirección IP seguida de un espacio
# Se usa el formato ${variable//buscar/reemplazar} para reemplazar todas las ocurrencias de 'buscar' con 'reemplazar' en 'variable'
# En este caso, 'buscar' es un espacio ' ' y 'reemplazar' es una cadena vacía ''
ip=${ip// /}
linea_a_agregar="    1 => '$ip', // Generado con script de automatización"

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
    if cat $config_file | grep "$ip"; then
        echo "Dominios de confianza corregidos."
        echo "Nextcloud está instalado y configurado correctamente."
        echo "Puede acceder a Nextcloud en http://$ip/ o http://localhost/."
    else
        echo "No se pudo corregir los dominios de confianza."
        echo "Nextcloud está instalado y configurado correctamente."
        echo "Puede acceder a Nextcloud en http://localhost/."
        echo "Para acceder a Nextcloud a través de la dirección IP, agregue la dirección IP a la lista de dominios de confianza en el archivo config.php."
    fi
    echo " - El usuario administrador de Nextcloud es 'admin'."
    echo " - La contraseña del administrador de Nextcloud es 'password'."
    echo "Recuerde cambiar la contraseña del administrador de Nextcloud por una más segura."
else
    echo "No se pudo reiniciar Apache. Saliendo..."
    exit
fi