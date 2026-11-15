dumpsys media.player > /data/local/tmp/mp.txt 2>&1
echo "decoder names + owner + flags:"
awk '/Decoder "/{name=$2} /owner:/{print name, $0} /attributes:/{print "   ", name, $0}' /data/local/tmp/mp.txt | head -40
echo; echo "=== goldfish / hardware mentions"; grep -n -iE "goldfish|hardware|software-only|isHardwareAccelerated|hw" /data/local/tmp/mp.txt | head -20
echo; echo "=== avc decoder block"; awk '/Decoder "c2.android.avc.decoder"/{f=1} f{print} /owner:/{if(f){exit}}' /data/local/tmp/mp.txt | head -40
echo; echo "=== all c2 decoder names"; grep -o 'Decoder "[^"]*"' /data/local/tmp/mp.txt | sort | head -40
echo; echo "=== c2 stores (lshal)"; lshal 2>/dev/null | grep -i IComponentStore
