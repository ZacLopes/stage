# Thumbnails dos templates de currículo

Esta pasta contém os PNGs de preview mostrados no `ResumeTemplateSelector`.

## Como regenerar

1. Rode o app em debug mode (`flutter run`)
2. Abra **Configurações** → **[DEV] Gerar thumbnails dos templates**
3. Toque em "Gerar 4 PNGs"
4. Copie o caminho mostrado na tela
5. No Finder: Cmd+Shift+G → cole o caminho
6. Mova os 4 PNGs daqui pra essa pasta (`assets/images/templates/`)
7. Commite os assets

## Arquivos esperados

- `harvard_ats.png`
- `jakes_resume.png`
- `forte_foundation.png`
- `one_page_compact.png`

Quando regerar: sempre que o HTML de algum template em `lib/features/resume/pdf_service.dart` mudar visualmente.
