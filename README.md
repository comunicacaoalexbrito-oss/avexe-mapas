# Mapas do Avexe

Mapas sem internet do app **Avexe**, um arquivo por região imediata do IBGE (a cidade e as cidades em volta).

- Gerados pelo GitHub Actions (`.github/workflows/mapas.yml`) no dia 5 de cada mês, ou à mão na aba **Actions › Mapas do Avexe › Run workflow**.
- Mapa enxuto: ruas, estradas, rios, áreas verdes, nomes e pontos (hospitais, postos de saúde, bombeiros, polícia, escolas, combustível), zoom até o nível da rua. Sem prédios e sem número de casa.
- Cada versão (Releases) tem `catalogo.txt` (regiões, cidades, tamanho e SHA-256), `fontes.zip` (letras do mapa) e `r<código IBGE>.pmtiles`.
- O app lê `https://github.com/<dono>/avexe-mapas/releases/latest/download/catalogo.txt`.

Dados © colaboradores do [OpenStreetMap](https://www.openstreetmap.org/copyright), licença ODbL. Regiões e cidades: IBGE. Ferramentas: Planetiler e pmtiles (Protomaps). Letras: Noto Sans (SIL Open Font License).
