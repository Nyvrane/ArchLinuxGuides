#!/bin/bash

# Renk kodları
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
CYAN='\e[36m'
NC='\e[0m' # No Color

# Root kontrolü
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}HATA: Lütfen bu betiği root yetkisiyle (sudo) çalıştırın.${NC}"
  echo "Örnek: sudo ./ble_sync_wizard.sh"
  exit 1
fi

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}   Bluetooth LE (BLE) Çift İşletim Sistemi Eşleyici ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""

# ADIM 1: Soru-Cevap
echo -e "${YELLOW}ADIM 1: Hazırlık Kontrolü${NC}"
echo "Bu betiğin doğru çalışması için cihazınızı şu sırayla eşleştirmiş olmanız gerekir:"
echo "1. Cihazı Linux'ta eşleştirin."
echo "2. Bilgisayarı kapatıp Windows'u açın."
echo "3. Cihazı Windows'ta eşleştirin (Kanal değiştirmeden!)."
echo ""
read -p "Cihazı yukarıdaki gibi en son Windows'ta eşleştirdiniz mi? (e/h): " ans
if [[ "$ans" != "e" && "$ans" != "E" ]]; then
    echo -e "${RED}Lütfen cihazı sırasıyla Linux ve ardından Windows'ta eşleştirin ve bu betiği tekrar çalıştırın.${NC}"
    exit 1
fi
echo -e "${GREEN}Harika. Devam ediyoruz...${NC}\n"

# ADIM 2: Kayıt Defteri
echo -e "${YELLOW}ADIM 2: Windows Kayıt Defteri (SYSTEM Hive)${NC}"
echo "Windows diskinizin Linux'a bağlı (mount edilmiş) olması gerekir."
echo "Otomatik olarak bilinen yolları arıyorum..."

# Yaygın mount noktalarında SYSTEM dosyasını ara
FOUND_PATHS=($(find /mnt /media /run/media -maxdepth 5 -type f -path "*/Windows/System32/config/SYSTEM" 2>/dev/null))

if [ ${#FOUND_PATHS[@]} -eq 0 ]; then
    echo -e "${RED}Otomatik aramada SYSTEM dosyası bulunamadı.${NC}"
    echo "Lütfen dosya yöneticinizden Windows diskinize tıklayarak bağlayın (mount edin)."
    echo "Örnek yol: /run/media/kullanici_adi/Windows/Windows/System32/config/SYSTEM"
    echo "Boş bırakırsanız mevcut test dosyası kullanılacaktır."
    read -p "SYSTEM dosyasının tam yolunu girin: " SYSTEM_PATH
else
    echo -e "${GREEN}Şu SYSTEM dosyaları bulundu:${NC}"
    for i in "${!FOUND_PATHS[@]}"; do
        echo "$((i+1)). ${FOUND_PATHS[$i]}"
    done
    read -p "Kullanmak istediğiniz dosyanın numarasını girin (1-${#FOUND_PATHS[@]}): " path_num
    
    if [[ "$path_num" =~ ^[0-9]+$ ]] && [ "$path_num" -ge 1 ] && [ "$path_num" -le "${#FOUND_PATHS[@]}" ]; then
        SYSTEM_PATH="${FOUND_PATHS[$((path_num-1))]}"
    else
        read -p "Manuel olarak yol girmek ister misiniz? (Dosya yolunu yazın veya çıkmak için boş bırakın): " SYSTEM_PATH
    fi
fi

if [ -z "$SYSTEM_PATH" ]; then
    SYSTEM_PATH="/home/night/.gemini/antigravity/scratch/SYSTEM_COPY"
fi

if [ ! -f "$SYSTEM_PATH" ]; then
    echo -e "${RED}Dosya bulunamadı: $SYSTEM_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}Kayıt defteri bulundu: $SYSTEM_PATH${NC}\n"

# ADIM 3: Adaptör MAC Adresi
echo -e "${YELLOW}ADIM 3: Bluetooth Adaptörü${NC}"
ADAPTER_MAC=$(echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\nls\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep -oE "<[0-9a-f]{12}>" | head -n 1 | tr -d '<>')

if [ -z "$ADAPTER_MAC" ]; then
    echo -e "${RED}Kayıt defterinde Bluetooth adaptörü bulunamadı.${NC}"
    exit 1
fi
LINUX_ADAPTER=$(echo $ADAPTER_MAC | sed 's/\(..\)/\1:/g; s/:$//' | tr '[:lower:]' '[:upper:]')
echo "Tespit edilen Adaptör MAC Adresi: $LINUX_ADAPTER"
echo ""

# ADIM 4: Hedef Cihaz Seçimi
echo -e "${YELLOW}ADIM 4: Cihaz MAC Adresi${NC}"
echo "Windows kayıt defterindeki eşleşmiş cihazlarınız şunlardır:"
echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\\\\$ADAPTER_MAC\nls\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep -E "<[0-9a-f]{12}>" | awk '{print "- " $2}'
echo ""
echo "Not: Aygıt adlarını tam doğrulamak isterseniz Windows'tan kontrol edebilirsiniz."
read -p "Bağlamak istediğiniz cihazın Windows MAC adresini (okların içindeki metni) bitişik harflerle girin (Örn: d17a7651f525): " WIN_MAC

if [ -z "$WIN_MAC" ]; then
    echo "İşlem iptal edildi."
    exit 1
fi

WIN_MAC=$(echo "$WIN_MAC" | tr -d '<>' | tr '[:upper:]' '[:lower:]')
LINUX_DEVICE=$(echo $WIN_MAC | sed 's/\(..\)/\1:/g; s/:$//' | tr '[:lower:]' '[:upper:]')
echo -e "${GREEN}Hedef Cihaz: $LINUX_DEVICE${NC}\n"

# ADIM 5: Veri Çekme ve Hesaplama
echo -e "${YELLOW}ADIM 5: Anahtarları Çıkarma ve Çevirme${NC}"
echo "chntpw ile hex verileri çekiliyor ve BlueZ formatına çevriliyor..."

LTK=$(echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\\\\$ADAPTER_MAC\\\\$WIN_MAC\nhex LTK\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep ":00000" | sed 's/.*:00000//' | cut -c 1-48 | tr -d ' ' | tr '[:lower:]' '[:upper:]')
EDIV_HEX=$(echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\\\\$ADAPTER_MAC\\\\$WIN_MAC\nhex EDIV\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep ":00000" | awk '{print $5$4$3$2}')
RAND_HEX=$(echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\\\\$ADAPTER_MAC\\\\$WIN_MAC\nhex ERand\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep ":00000" | awk '{print $9$8$7$6$5$4$3$2}')
IRK=$(echo -e "cd ControlSet001\\\\Services\\\\BTHPORT\\\\Parameters\\\\Keys\\\\$ADAPTER_MAC\\\\$WIN_MAC\nhex IRK\nq" | chntpw -e "$SYSTEM_PATH" 2>/dev/null | grep ":00000" | sed 's/.*:00000//' | cut -c 1-48 | tr -d ' ' | tr '[:lower:]' '[:upper:]')

if [ -z "$LTK" ]; then
    echo -e "${RED}HATA: LTK (Long Term Key) bulunamadı. Cihaz BLE olmayabilir veya eşleşmemiş olabilir.${NC}"
    exit 1
fi

# Hex'ten Decimal'e çevrim işlemleri
EDIV_DEC=$(printf "%d" "0x$EDIV_HEX" 2>/dev/null || echo "0")
RAND_DEC=$(printf "%llu" "0x$RAND_HEX" 2>/dev/null || echo "0")

echo "LTK: $LTK"
echo "EDIV: $EDIV_DEC"
echo "RAND: $RAND_DEC"
if [ ! -z "$IRK" ]; then
    echo "IRK: $IRK"
fi
echo ""

# ADIM 6: Dosyaya Yazma
echo -e "${YELLOW}ADIM 6: Linux Bluetooth Yapılandırmasını Güncelleme${NC}"
BLUEZ_DIR="/var/lib/bluetooth/$LINUX_ADAPTER/$LINUX_DEVICE"
INFO_FILE="$BLUEZ_DIR/info"

echo "DİKKAT: Cihaz şu an Linux tarafında farklı bir MAC adresiyle eşleşmiş görünüyorsa,"
echo "lütfen başka bir terminal açıp 'bluetoothctl remove [ESKİ_MAC]' komutuyla onu silin."
read -p "Eski eşleşmeyi sildiyseniz devam etmek için Enter'a basın..."

mkdir -p "$BLUEZ_DIR"

cat <<EOF > "$INFO_FILE"
[General]
Name=Bluetooth_Device
SupportedTechnologies=LE;
Trusted=true
Blocked=false

EOF

if [ ! -z "$IRK" ]; then
cat <<EOF >> "$INFO_FILE"
[IdentityResolvingKey]
Key=$IRK

EOF
fi

cat <<EOF >> "$INFO_FILE"
[LongTermKey]
Key=$LTK
Authenticated=0
EncSize=16
EDiv=$EDIV_DEC
Rand=$RAND_DEC
EOF

chmod -R 700 "/var/lib/bluetooth/$LINUX_ADAPTER"
echo -e "${GREEN}BlueZ info dosyası başarıyla oluşturuldu: $INFO_FILE${NC}\n"

# ADIM 7: Yeniden Başlatma
echo -e "${YELLOW}ADIM 7: Servisi Yeniden Başlatma${NC}"
systemctl restart bluetooth
echo -e "${GREEN}Bluetooth servisi yeniden başlatıldı.${NC}\n"
echo -e "${CYAN}İŞLEM TAMAMLANDI!${NC} Cihazınızın tuşlarına basarak Linux'a anında bağlanmasını sağlayabilirsiniz."
