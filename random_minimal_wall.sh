#!/usr/bin/env bash

# Скрипт для выбора топовых минималистичных обоев (DenverCoder1)
# Оптимизирован для скорости: кэширует список файлов.

# --- Настройки ---
REPO="DenverCoder1/minimalistic-wallpaper-collection"
BRANCH="main"
SUBDIR="images"

# Пути
QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="$HOME/.cache/ii-wallpapers"
LIST_CACHE="$CACHE_DIR/file_list.txt"
PREVIEW_FILE="/tmp/wall_current.jpg"

SWITCHWALL_SCRIPT="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME/scripts/colors/switchwall.sh"

# --- Функции ---
get_pictures_dir() {
    if [ -d "$HOME/Pictures" ]; then
        echo "$HOME/Pictures"
        return
    fi
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi
    echo "$HOME"
}

check_dependencies() {
    local missing=()
    for cmd in curl jq shuf; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo "Ошибка: нужны утилиты: ${missing[*]}"
        exit 1
    fi
}

# --- Инициализация ---
check_dependencies
mkdir -p "$CACHE_DIR"
PICTURES_DIR=$(get_pictures_dir)
if [ -d "$PICTURES_DIR/wallpapers" ]; then
    WALLPAPER_DIR="$PICTURES_DIR/wallpapers/minimalist"
else
    WALLPAPER_DIR="$PICTURES_DIR/Pictures/wallpapers/minimalist"
fi
mkdir -p "$WALLPAPER_DIR"

# Папка для сохранений ("избранное")
# Создаем в директории скрипта или в рабочей папке
WORK_DIR="/home/droopi/WorkSpace/ii-minimal-wallpaper"
SAVES_DIR="$WORK_DIR/saves"
mkdir -p "$SAVES_DIR"

cleanup() { rm -f "$PREVIEW_FILE"; stty sane; }
trap cleanup EXIT
stty sane

# --- Получение списка (Кэширование) ---
echo "--- Инициализация ---"
if [[ ! -f "$LIST_CACHE" ]] || [[ $(find "$LIST_CACHE" -mmin +60) ]]; then
    echo "Загрузка списка обоев с GitHub (обновление кэша)..."
    API_URL="https://api.github.com/repos/$REPO/contents/$SUBDIR?ref=$BRANCH"
    
    # Получаем список файлов (фильтр по картинкам)
    RESPONSE=$(curl -s "$API_URL")
    
    # Проверка на лимиты API
    if echo "$RESPONSE" | grep -q "API rate limit"; then
        echo "Предупреждение: Лимит API GitHub. Пробую парсить HTML..."
        curl -sL "https://github.com/$REPO/tree/$BRANCH/$SUBDIR" \
        | grep -oP '"name":"[^"]+\.(jpg|jpeg|png|webp)"' \
        | cut -d'"' -f4 | sort -u \
        | sed "s|^|https://raw.githubusercontent.com/$REPO/$BRANCH/$SUBDIR/|" > "$LIST_CACHE"
    else
        echo "$RESPONSE" | jq -r '.[] | select(.type == "file") | .download_url' > "$LIST_CACHE"
    fi
else
    echo "Использую кэшированный список ($(wc -l < "$LIST_CACHE") файлов)."
fi

# Проверка списка
if [[ ! -s "$LIST_CACHE" ]]; then
    echo "Ошибка: Список обоев пуст. Проверьте интернет."
    rm -f "$LIST_CACHE"
    exit 1
fi

# Читаем список в массив и перемешиваем
mapfile -t ALL_URLS < "$LIST_CACHE"
SHUFFLED_URLS=($(printf "%s\n" "${ALL_URLS[@]}" | shuf))
TOTAL=${#SHUFFLED_URLS[@]}
INDEX=0

echo "Найдено $TOTAL обоев. Поехали!"
sleep 0.5

# --- Главный цикл ---
while true; do
    CURRENT_URL="${SHUFFLED_URLS[$INDEX]}"
    FILE_NAME=$(basename "$CURRENT_URL")
    
    clear
    echo "Обои [$((INDEX+1))/$TOTAL] | Файл: $FILE_NAME"
    echo "Загрузка..."
    
    # Скачиваем текущую
    curl -L -s "$CURRENT_URL" -o "$PREVIEW_FILE"
    
    if [[ ! -s "$PREVIEW_FILE" ]]; then
        echo "Ошибка скачивания. Следующая..."
        INDEX=$(( (INDEX + 1) % TOTAL ))
        continue
    fi

    clear
    echo "Обои [$((INDEX+1))/$TOTAL] | Файл: $FILE_NAME"
    echo "--------------------------------------------------"
    if command -v chafa &> /dev/null; then
        chafa --size=80x25 "$PREVIEW_FILE"
    else
        echo "(Установите chafa для просмотра картинок)"
    fi
    echo "--------------------------------------------------"
    echo -e " [←] Влево  : Назад"
    echo -e " [→] Вправо : Дальше"
    echo -e " [s]        : СОХРАНИТЬ в saves (избранное)"
    echo -e " [Enter]    : ПРИМЕНИТЬ и Выход"
    echo -e " [q]        : Выход"
    
    # Чтение клавиш
    while true; do
        read -rsn1 key < /dev/tty
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 key2 < /dev/tty
            if [[ "$key2" == "[C" ]]; then # Вправо
                INDEX=$(( (INDEX + 1) % TOTAL ))
                break
            elif [[ "$key2" == "[D" ]]; then # Влево
                # Добавляем TOTAL, чтобы не уйти в минус
                INDEX=$(( (INDEX - 1 + TOTAL) % TOTAL ))
                break
            fi
        fi
        
        if [[ "$key" == "s" || "$key" == "S" ]]; then
            cp "$PREVIEW_FILE" "$SAVES_DIR/$FILE_NAME"
            echo -e "\n [OK] Сохранено в: $SAVES_DIR/$FILE_NAME"
            sleep 0.5
            # Перерисовываем меню, чтобы скрыть сообщение или просто продолжаем
            break # Прерываем ожидание ввода, чтобы перерисовать интерфейс (но останемся на той же картинке, если не менять INDEX)
        fi

        if [[ -z "$key" ]]; then # Enter
            echo "Применяю..."
            FINAL_PATH="$WALLPAPER_DIR/$FILE_NAME"
            mv "$PREVIEW_FILE" "$FINAL_PATH"
            
            if [[ -f "$SWITCHWALL_SCRIPT" ]]; then
                bash "$SWITCHWALL_SCRIPT" --image "$FINAL_PATH" > /dev/null 2>&1
            elif command -v hyprpaper &> /dev/null; then
                hyprctl hyprpaper unload all > /dev/null 2>&1
                hyprctl hyprpaper preload "$FINAL_PATH" > /dev/null 2>&1
                MONITORS=$(hyprctl monitors -j | jq -r '.[] | .name')
                for MON in $MONITORS; do
                    hyprctl hyprpaper wallpaper "$MON,$FINAL_PATH" > /dev/null 2>&1
                done
            fi
            echo "Готово!"
            exit 0
        fi
        
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            exit 0
        fi
    done
    
    # Если мы нажали 's', мы вышли из цикла ввода, но INDEX не изменился (если бы мы нажали стрелку, он бы изменился).
    # Нужно проверить это, чтобы не перезагружать ту же картинку бесконечно, если мы нажали S.
    # Но в текущей логике 'break' в S приведет к началу цикла `while true`, который СНОВА скачает ту же картинку (так как INDEX тот же).
    # Это может быть лишней тратой, но зато обновит интерфейс. 
    # Чтобы не скачивать заново, можно проверить наличие PREVIEW_FILE, но curl перезапишет.
    # Оставим так, "моргание" экрана после сохранения подскажет, что действие прошло.
done
