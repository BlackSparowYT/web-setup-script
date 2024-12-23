#!/bin/bash

# Function to ask for input
ask_for_input() {
    local prompt=$1
    local var_name=$2
    read -p "$prompt" input
    eval "$var_name='$input'"
}

# Create necessary directories
for dir in laravel react docker plain; do
    mkdir -p "/var/www/$dir"
done

# Ask for domain and project type
ask_for_input "Enter the domain you want to use: " domain
ask_for_input "What do you want to create (laravel/react/docker/plain)? " project_type

# Ask for GitHub repo link (optional)
ask_for_input "Enter the GitHub repo link (leave empty if not applicable): " repo_link

# Ask if the GitHub link should be used as a template
if [[ -n "$repo_link" ]]; then
    ask_for_input "Should this GitHub link be used as a template? (yes/no): " use_as_template
else
    use_as_template="no"
fi

# Ask if it's a static site (only for plain site)
if [[ "$project_type" == "plain" ]]; then
    ask_for_input "Is this a static/plain site? (default: yes) [yes/no]: " is_static
    [[ -z "$is_static" ]] && is_static="yes"
fi

# Set the base directory based on the project type
if [[ "$project_type" == "plain" && "$is_static" == "yes" ]]; then
    domain_dir="/var/www/plain/$domain"
elif [[ "$project_type" == "plain" && "$is_static" == "no" ]]; then
    domain_dir="/var/www/$domain"
else
    domain_dir="/var/www/$project_type/$domain"
fi

mkdir -p "$domain_dir"
sudo chown -R www-data:www-data "$domain_dir"

# Check if there are existing files in the directory
if [ "$(ls -A "$domain_dir")" ]; then
    echo -e "\e[33mIt seems there are already files in the folder: $domain_dir.\e[0m"
    
    # Identify the type of project based on existing files
    if [[ -f "$domain_dir/composer.json" ]]; then
        echo -e "\e[33mThis appears to be a Laravel project.\e[0m"
    elif [[ -f "$domain_dir/package.json" ]]; then
        echo -e "\e[33mThis appears to be a React project.\e[0m"
    elif [[ -f "$domain_dir/Dockerfile" ]]; then
        echo -e "\e[33mThis appears to be a Docker project.\e[0m"
    else
        echo -e "\e[33mNo recognizable project files found.\e[0m"
    fi

    # Ask whether to keep or remove the existing files
    echo "Do you want to keep the existing files?"
    echo "If opt not to keep the files but the folder contains a .env we will save the .env for you."
    ask_for_input  "(yes/no): " keep_files

    if [[ "$keep_files" == "no" || "$keep_files" == "n" ]]; then
        ask_for_input "Are you sure you want to remove all files in $domain_dir? (yes/no): " confirm_remove
        if [[ "$confirm_remove" == "yes" || "$confirm_remove" == "y" ]]; then
            find "$domain_dir" -mindepth 1 ! -name '.env' -delete
            echo -e "\e[32mAll files have been removed from $domain_dir.\e[0m"
            mkdir -p "$domain_dir"
        else
            echo -e "\e[33mKeeping the existing files in $domain_dir.\e[0m"
            skip_setup=true
        fi
    else
        echo -e "\e[33mKeeping the existing files in $domain_dir.\e[0m"
        skip_setup=true
    fi
fi

cd "$domain_dir" || exit

# Set up based on project type if not skipping
if [ -z "$skip_setup" ]; then
    case "$project_type" in
        laravel)
            if [ -n "$repo_link" ]; then
                if [ -f "$domain_dir/.env" ]; then
                    cd /var/www/laravel || exit
                    mv "$domain_dir/.env" "/var/www/laravel/${domain}.env"
                    rm -rf "$domain_dir"
                    mkdir -p "$domain_dir"
                fi

                git clone "$repo_link" "$domain_dir"
                cd "$domain_dir" || exit

                if [ -f "/var/www/laravel/${domain}.env" ]; then
                    mv "/var/www/laravel/${domain}.env" "$domain_dir/.env"
                fi

                if [[ "$use_as_template" == "yes" ]]; then
                    rm -rf .git
                    git init
                    git branch -m main
                fi
                
                echo "When asked to confirm running composer as root, type 'yes'."
                composer install

                if [ ! -f ".env" ]; then
                    echo -e "\e[31mYou will need to upload your .env file !!\e[0m"
                    echo -e "\e[31mYou will need to manually run 'php artisan key:generate' !!\e[0m"
                    echo -e "\e[33m5. The script will proceed in 5 sec.\e[0m"
                    sleep 5
                else
                    php artisan key:generate
                fi
                php artisan storage:link
                sudo chown -R www-data:www-data "$domain_dir"/storage "$domain_dir"/bootstrap/cache
            else
                ask_for_input "No GitHub link provided. Choose setup option: (1) Plain Laravel, (2) Nothing: " setup_option

                case "$setup_option" in
                    1)
                        composer create-project --prefer-dist laravel/laravel "$domain_dir"
                        cd "$domain_dir" || exit
                        git init
                        git branch -m main
                        composer install

                        if [ ! -f ".env" ]; then
                            echo -e "\e[31mYou will need to upload your .env file !!\e[0m"
                            echo -e "\e[31mYou will need to manually run 'php artisan key:generate' !!\e[0m"
                            echo -e "\e[33m5. The script will proceed in 5 sec.\e[0m"
                            sleep 5
                        else
                            php artisan key:generate
                        fi
                        php artisan storage:link
                        sudo chown -R www-data:www-data "$domain_dir"/storage "$domain_dir"/bootstrap/cache
                        ;;
                    2)
                        echo -e "\e[33mYou have not provided a GitHub repo or chosen to set up a default installation, please manually upload the files and do the following:\e[0m"
                        echo -e "\e[33m1. Run 'composer install' to install the dependencies.\e[0m"
                        echo -e "\e[33m2. Run 'php artisan key:generate' to generate the application key.\e[0m"
                        echo -e "\e[33m3. Run 'php artisan storage:link' to create the storage symlink.\e[0m"
                        echo -e "\e[33m4. Run 'sudo chown -R www-data:www-data $domain_dir/storage $domain_dir/bootstrap/cache' to set up the correct permissions.\e[0m"
                        echo -e "\e[33mThe script will proceed in 10 sec to generate an nginx config file and try to set up SSL.\e[0m"
                        sleep 10
                        ;;
                    *)
                        echo -e "\e[31mInvalid option selected. Exiting...\e[0m"
                        exit 1
                        ;;
                esac
            fi
            ;;

        react)
            if [ -n "$repo_link" ]; then
                git clone "$repo_link" "$domain_dir"
                cd "$domain_dir" || exit

                if [[ "$use_as_template" == "yes" ]]; then
                    rm -rf .git
                    git init
                    git branch -m main
                fi

                npm install
                npm run build

                if [ ! -d "dist" ]; then
                    echo -e "\e[31m'dist' folder not found. Build may have failed. Exiting.\e[0m"
                    echo -e "\e[31mPlease check why the build fails and rerun the script or continue manually.\e[0m"
                    exit 1
                fi
            else
                ask_for_input "No GitHub link provided. Would you like to set up a default React installation? (yes/no): " setup_default

                if [[ "$setup_default" == "yes" || "$setup_default" == "y" ]]; then
                    npx create-react-app "$domain_dir"
                    cd "$domain_dir" || exit

                    npm install
                    npm run build
                    
                    if [ ! -d "dist" ]; then
                        echo -e "\e[31m'dist' folder not found. Build may have failed. Exiting.\e[0m"
                        echo -e "\e[31mPlease check why the build fails and rerun the script or continue manually.\e[0m"
                        exit 1
                    fi
                else
                    echo -e "\e[33mYou have not provided a GitHub repo or chosen to set up a default installation. Please manually upload the files and do the following:\e[0m"
                    echo -e "\e[33m1. Run 'npm install' to install the dependencies.\e[0m"
                    echo -e "\e[33m2. Run 'npm run build' to build the project.\e[0m"
                    echo -e "\e[33mThe script will proceed in 10 seconds to generate an Nginx config file and try to set up SSL.\e[0m"
                    sleep 10
                fi
            fi
            ;;

        docker)
            if [ -n "$repo_link" ]; then
                git clone "$repo_link" "$domain_dir"
                cd "$domain_dir" || exit
            else
                echo -e "\e[31mPlease provide a GitHub link to set up Docker project.\e[0m"
                exit 1
            fi
            ;;

        plain)
            if [[ "$is_static" == "yes" ]]; then
                echo -e "\e[32mSetting up static site files in $domain_dir.\e[0m"
            else
                echo -e "\e[32mSetting up plain dynamic site files in $domain_dir.\e[0m"
            fi
            ;;
        *)
            echo -e "\e[31mInvalid project type selected. Exiting...\e[0m"
            exit 1
            ;;
    esac
fi

# Create nginx config file
nginx_config="/etc/nginx/sites-available/$domain.conf"
case "$project_type" in
    laravel)
        cat <<EOL > "$nginx_config"
server {
    listen 80;
    server_name $domain;

    root $domain_dir/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL
        ;;
    react)
        cat <<EOL > "$nginx_config"
server {
    listen 80;
    server_name $domain;

    root $domain_dir/dist;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }
}
EOL
        ;;
    docker)
        cat <<EOL > "$nginx_config"
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
        ;;
    plain)
        cat <<EOL > "$nginx_config"
server {
    listen 80;
    server_name $domain;

    root $domain_dir;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock; # Adjust for your PHP version
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOL
        ;;
esac

# Create symlink to sites-enabled
ln -sf "$nginx_config" "/etc/nginx/sites-enabled/"

# Test nginx configuration
nginx -t
if [ $? -ne 0 ]; then
    echo -e "\e[31mNginx configuration test failed. Exiting script. Please check the nginx configuration file for any errors\e[0m"
    echo -e "\e[31mYou can check the configuration file at $nginx_config\e[0m"
    echo -e "\e[31mAfter having resolved the error(s), you can run 'nginx -t' to test the configuration\e[0m"
    echo -e "\e[31mOnce the test has completed succesfully and you would like to add SSL please run 'certbot --nginx -d $domain'\e[0m"
    exit 1
fi

# Reload nginx to apply changes
systemctl reload nginx

# Run certbot for SSL
certbot --nginx -d "$domain"

# Check if certbot was successful
if [ $? -ne 0 ]; then
    echo -e "\e[31mCertbot SSL setup failed. Exiting script. Please read above why this has failed.\e[0m"
    echo -e "\e[31mAfter having resolved the error(s) you can retry with 'certbot --nginx -d $domain'\e[0m"
    exit 1
fi

echo "Certbot SSL setup completed successfully."

echo "Script completed successfully."
