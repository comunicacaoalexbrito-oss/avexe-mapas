#!/usr/bin/env bash
# Avexe - gera os mapas sem internet (Fase 3, Lote B). Roda no GitHub Actions (ver .github/workflows/mapas.yml).
#
#  1. baixa o Planetiler e o pmtiles (programas livres);
#  2. baixa o mapa do Brasil (OpenStreetMap, Geofabrik) e monta um mapa enxuto (perfil OpenMapTiles):
#     sem predios, sem numero de casa, sem picos e aeroportos, zoom ate o nivel da rua (14);
#  3. pega as regioes imediatas do IBGE (510) e corta um arquivo .pmtiles por regiao (caixa + 3 km);
#  4. faz o catalogo (catalogo.txt) e o pacote de letras do mapa (fontes.zip).
#
# Variaveis: REGIAO (opcional: so uma regiao, pelo codigo do IBGE ou nome de uma cidade, para teste rapido),
#            BASE_URL (endereco de download dos arquivos da versao), MEMORIA (ex.: 10g).
# Dados: (c) colaboradores do OpenStreetMap (ODbL). Regioes e cidades: IBGE.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p trabalho saida
cd trabalho
REGIAO="${REGIAO:-}"
MEMORIA="${MEMORIA:-10g}"
IBGE="https://servicodados.ibge.gov.br/api"

echo "== 1. Programas"
[ -f planetiler.jar ] || curl -fsSL -o planetiler.jar https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar
if [ ! -x pmtiles ]; then
  url=$(curl -fsSL https://api.github.com/repos/protomaps/go-pmtiles/releases/latest \
        | jq -r '.assets[] | select(.name | test("Linux_x86_64\\.tar\\.gz$")) | .browser_download_url' | head -n1)
  [ -n "$url" ] || { echo "nao achei o pmtiles para Linux"; exit 1; }
  curl -fsSL "$url" | tar -xz pmtiles
fi
java -version

echo "== 2. Regioes do IBGE"
# O site do IBGE as vezes nao responde para computadores fora do Brasil (o GitHub roda nos EUA).
# Por isso: tenta 3 vezes; se nao der, usa a copia guardada na pasta ibge/ do repositorio.
# A copia pode estar em ibge/ ou IBGE/, e a lista de regioes pode se chamar regioes.json ou regioes-imediatas.json.
copia_ibge() {
  local nomes="$1"
  [ "$1" = regioes.json ] && nomes="regioes.json regioes-imediatas.json"
  [ "$1" = malha.geojson ] && nomes="malha.geojson malha.json BR BR.json BR.geojson"
  for pasta in ../ibge ../IBGE ../Ibge; do
    for n in $nomes; do
      if [ -s "$pasta/$n" ] && head -c 1 "$pasta/$n" | grep -q '[[{]'; then echo "$pasta/$n"; return 0; fi
    done
  done
  return 1
}
ibge() {  # ibge <arquivo> <endereco>
  if curl -fsSL --retry 3 --retry-delay 15 --connect-timeout 30 --max-time 300 -o "$1" "$2" && [ -s "$1" ]; then
    echo "  $1: baixado do IBGE"
  elif copia=$(copia_ibge "$1"); then
    cp "$copia" "$1"; echo "  $1: copia de $copia"
  else
    echo "ERRO: o IBGE nao respondeu e nao ha copia em ibge/$1."
    echo "Baixe pelo navegador e envie para a pasta ibge/ do repositorio (veja o guia, passo 4b):"
    echo "  $2"
    exit 1
  fi
}
ibge regioes.json "$IBGE/v1/localidades/regioes-imediatas"
ibge municipios.json "$IBGE/v1/localidades/municipios"
ibge malha.geojson "$IBGE/v3/malhas/paises/BR?formato=application/vnd.geo%2Bjson&intrarregiao=regiao-imediata&qualidade=minima"
echo "regioes: $(jq length regioes.json) · municipios: $(jq length municipios.json) · formas: $(jq '.features | length' malha.geojson)"

# Caixa (oeste sul leste norte) de cada forma.
jq -r '.features[] | [.properties.codarea,
   ([.geometry.coordinates | .. | arrays | select(length == 2 and (.[0] | type) == "number")] as $p
    | ($p | map(.[0]) | min), ($p | map(.[1]) | min), ($p | map(.[0]) | max), ($p | map(.[1]) | max))] | @tsv' \
   malha.geojson > caixas.tsv

# Teste: aceita o codigo da regiao ou o nome de uma cidade ("Garanhuns", "Lauro de Freitas").
if [ -n "$REGIAO" ] && ! [[ "$REGIAO" =~ ^[0-9]+$ ]]; then
  achado=$(jq -r --arg c "$REGIAO" '.[] | select((.nome | ascii_downcase) == ($c | ascii_downcase)) | select(.["regiao-imediata"] != null)
           | "\(.["regiao-imediata"].id)\t\(.nome)\t\(.["regiao-imediata"].nome)"' municipios.json | head -n1)
  [ -n "$achado" ] || { echo "nao achei a cidade '$REGIAO' no IBGE (escreva como no IBGE, com acento)"; exit 1; }
  echo "Cidade: $achado"
  REGIAO=$(echo "$achado" | cut -f1)
fi
LIMITES=""
if [ -n "$REGIAO" ]; then
  read -r _ o s l n < <(grep -P "^$REGIAO\t" caixas.tsv) || { echo "regiao $REGIAO nao existe no IBGE"; exit 1; }
  LIMITES=$(awk -v o="$o" -v s="$s" -v l="$l" -v n="$n" 'BEGIN { printf "--bounds=%.4f,%.4f,%.4f,%.4f", o - 0.05, s - 0.05, l + 0.05, n + 0.05 }')
  echo "Teste com uma regiao: $REGIAO ($LIMITES)"
fi

echo "== 3. Mapa do Brasil enxuto (Planetiler)"
if [ ! -f brasil.pmtiles ]; then
  java "-Xmx$MEMORIA" -jar planetiler.jar \
    --area=brazil --download --download-threads=8 \
    --output=brasil.pmtiles --force \
    --max-zoom=14 \
    --exclude-layers=building,housenumber,aerodrome_label,mountain_peak \
    --languages=pt \
    $LIMITES
fi
ls -lh brasil.pmtiles

echo "== 4. Um arquivo por regiao"
jq -r '.[] | select(.["regiao-imediata"] != null) | [(.["regiao-imediata"].id | tostring), .nome] | @tsv' municipios.json | sort -t$'\t' -k1,1 -k2,2 > cidades.tsv
: > ../saida/linhas.tsv
total=$(jq length regioes.json)
i=0
while IFS=$'\t' read -r id nome uf; do
  i=$((i + 1))
  if [ -n "$REGIAO" ] && [ "$id" != "$REGIAO" ]; then continue; fi
  linha=$(grep -P "^$id\t" caixas.tsv || true)
  if [ -z "$linha" ]; then echo "  sem forma: $id $nome (pulei)"; continue; fi
  # Corta pela caixa da regiao com folga de ~3 km: quem mora na divisa nao fica sem as ruas de perto.
  corte=$(echo "$linha" | awk -F'\t' '{ printf "%.4f,%.4f,%.4f,%.4f", $2 - 0.03, $3 - 0.03, $4 + 0.03, $5 + 0.03 }')
  arq="../saida/r$id.pmtiles"
  ./pmtiles extract brasil.pmtiles "$arq" --bbox="$corte" > /dev/null
  bytes=$(stat -c %s "$arq")
  sha=$(sha256sum "$arq" | cut -d' ' -f1)
  caixa=$(grep -P "^$id\t" caixas.tsv | cut -f2-5 | awk -F'\t' '{printf "%.5f\t%.5f\t%.5f\t%.5f", $1, $2, $3, $4}' || true)
  cidades=$(grep -P "^$id\t" cidades.tsv | cut -f2 | tr ';\t' '  ' | paste -sd ';' - || true)
  printf 'R\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$nome" "$uf" "$bytes" "$sha" "$caixa" "$cidades" >> ../saida/linhas.tsv
  printf '  %3d/%d %s (%s) %s\n' "$i" "$total" "$nome" "$uf" "$(numfmt --to=iec "$bytes")"
done < <(jq -r '.[] | [(.id | tostring), .nome, .["regiao-intermediaria"].UF.sigla] | @tsv' regioes.json | sort)

echo "== 5. Catalogo e letras"
{
  printf 'AVEXE_MAPAS\t1\t%s\t%s\t(c) colaboradores do OpenStreetMap; regioes: IBGE\n' "$(date -u +%Y-%m-%d)" "${BASE_URL:-}"
  cat ../saida/linhas.tsv
} > ../saida/catalogo.txt
rm ../saida/linhas.tsv
echo "catalogo: $(grep -c '^R' ../saida/catalogo.txt) regioes"

rm -rf fontes && mkdir -p fontes
for fonte in "Noto Sans Regular" "Noto Sans Medium" "Noto Sans Italic"; do
  mkdir -p "fontes/$fonte"
  for faixa in 0-255 256-511 8192-8447; do
    curl -fsSL -o "fontes/$fonte/$faixa.pbf" \
      "https://raw.githubusercontent.com/protomaps/basemaps-assets/main/fonts/${fonte// /%20}/$faixa.pbf"
  done
done
(cd fontes && zip -qr ../../saida/fontes.zip .)
du -sh ../saida
