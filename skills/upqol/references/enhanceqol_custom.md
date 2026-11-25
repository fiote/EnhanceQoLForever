# EnhanceQoL Forever: contexto e customizações locais

Registro inicial da skill em 24/11/2026. Confira o estado atual em disco antes de usar estas informações para uma atualização.

**Instalado agora: 13.24.2 Forever + customizações locais.**

## Instalação

- Checkout ativo: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLRepo`.
- Remoto: `https://github.com/fiote/EnhanceQoLForever`, branch observada `master`.
- HEAD observado ao criar a skill: `82e0a601169b6454a4d84914b3fa3c961d00c8c2`, sincronizado com `origin/master`, sem alterações pendentes.
- TOC carregado no cliente Forever: `EnhanceQoL/EnhanceQoL_Camelot.toc`, versão **13.24.2**, interface **16001**, `X-EQOL-Flavor: forever`.
- Projeto CurseForge indicado pelo TOC: **1076354**. Pacotes originais confirmados: `EnhanceQoL-13.23.0-forever.zip` (file ID 9680343) e `EnhanceQoL-13.24.0-forever.zip` (file ID 9800290) e `EnhanceQoL-13.24.1-forever.zip` (file ID 9807437) e `EnhanceQoL-13.24.2-forever.zip` (file ID 9815741). Preserve o original 13.24.2 como base da próxima atualização; IDs, URLs e hashes estão no manifesto da preparação.
- As 18 pastas `EnhanceQoL*` em `Interface/AddOns` são junctions para os módulos do checkout externo. Preserve esses links. A cópia antiga em `Interface/Workspace` não é um destino de trabalho.
- Dados da atualização: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater`, fora do Git e da instalação do jogo.

Não use `0ac1c64` (commit inicial do fork) como se fosse o ZIP original do autor. Ele já contém uma árvore adaptada ao Forever; a comparação com a base oficial da versão instalada é necessária para inventariar todas as diferenças.

## Customizações introduzidas nesta conversa

### Classe/especialização por spell — `d5f27d6`

Em **Spells → General → Display**, cada entrada pode restringir classe ou usar **Use spec filter** com os grupos de talentos do Forever, reutilizando as opções dos painéis. Preserve seleções por entrada, a opção de todas as classes/specs, a combinação dos filtros e o reset da aba. IDs Retail importados continuam separados dos grupos de talentos Forever.

Arquivos principais: `CooldownPanels_ClassFilters_Camelot.lua`, `CooldownPanels_Camelot.lua`, `CooldownPanels_Helper.lua` e `Navigation.lua`, em `EnhanceQoLCooldownPanels`.

### Stance/form por spell — `82e0a60`

Em **Spells → General → Display**, **Show only in stance/form** usa as stances/forms da classe atual e os nomes fornecidos pelo cliente. A forma normal do druida e a opção sem restrição são selecionáveis. A seleção usa classe + spell ID, com normalização de substituições como Urso/Dire Bear, em vez da posição na barra de formas.

A restrição combina com classe/spec e afeta **somente o painel exibido no jogo**. A lista lateral de edição deve conservar o spell ao trocar de postura, inclusive com a opção de ocultar indisponíveis ligada. Preserve a separação entre `EntryAllowsSpec` (usado na disponibilidade do editor) e `EntryAllowsRuntimeFilters` (que acrescenta stance/form). Não reintroduza a consulta de stance no predicado da lista lateral.

Arquivos principais: `CooldownPanels_Stance_Camelot.lua`, `CooldownPanels_Camelot.lua`, `CooldownPanels_Helper.lua`, `CooldownPanels_AuraContainers.lua`, `Navigation.lua` e traduções `EnhanceQoL/Locales/enUS.lua` e `ptBR.lua`.

Foram executados testes Lua de sintaxe, seleção/reset, cache após troca de postura, reordenação/substituição das formas, combinação com classe/spec e preservação da lista de edição. O usuário confirmou o filtro no jogo e relatou a falha da lista lateral; a correção foi implementada e testada em Lua antes do commit. Não há confirmação posterior de teste visual dessa correção.

## Outras diferenças

Este documento não é um inventário completo do commit inicial. Antes de atualizar, compare todos os módulos com o ZIP original da versão efetivamente instalada — agora **13.24.2 Forever**. Inspecione também TOCs/XML Camelot, compatibilidade de APIs, grupos de talentos e os demais componentes `*_Camelot`. Não apague uma adaptação só porque ela não aparece na lista acima.

O nome de um arquivo `_Camelot` por si só não prova que seja uma customização nossa: ele pode vir do autor. Registre a origem com base na comparação real.

## Histórico de atualizações pela skill

### 13.23.0 → 13.24.0 Forever

Atualização aplicada após aprovação explícita do usuário, com o WoW fechado. Base original 13.23.0: file ID 9680343; pacote novo 13.24.0: file ID 9800290. As árvores originais, ZIPs e manifesto foram preservados fora do Git.

- Comparação com a base: 8 arquivos tinham customizações locais. O autor modificou 110 arquivos e acrescentou 10, sem remoções. Dois arquivos locais foram mantidos integralmente e seis mesclados sem conflitos. Nenhuma customização foi retirada ou considerada obsoleta.
- Preservados: classe/spec por spell, stance/form, seleção sem restrição, reset e traduções, e a lista lateral de edição independente da postura.
- Adaptação para a novidade do autor: `CooldownPanels_HoverBuffPanel.lua` usa `EntryAllowsRuntimeFilters` no painel em execução e mantém o preview completo. O teste confirmou que a stance altera a listagem do painel sem retirar os spells do editor.
- Os 18 módulos e suas junctions foram preservados; os 1.273 arquivos instalados conferem com os hashes do merge revisado. Backup verificado dos 1.263 arquivos anteriores: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/EnhanceQoL-13.23.0-mods-backup`.
- CurseForge standalone sincronizado com o file ID 9800290 e reaberto. Backup do registro: `EnhanceQoLUpdater/.upqol/AddonGameInstance.before-13.24.0.json`. A gravação preservou as demais entradas. SavedVariables não foram alteradas.
- Retenção: versões 13.24.0 e 13.23.0 preservadas, incluindo o ZIP original da instalada. Nenhuma exclusão era necessária ou foi executada.
- Validações: 80 arquivos Lua compilados em Lua 5.1, 36 TOCs na versão nova, 408 referências de carregamento conferidas, sem conflitos, novas misturas de finais de linha ou linhas customizadas perdidas. Passaram os testes de classe/spec, stance/form, cache, reset, lista lateral e Hover Buff Panel. Não houve teste dentro do jogo.
- Git: skill versionada em `38dd89b`; atualização identificada pelo commit `v13.24.0` em `master`. O resultado do push fica no manifesto.

Preparação e evidências: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/.upqol/preparation-13.23.0-to-13.24.0-fda3a4efbc/`. Prioridades para conferir no jogo: filtros e lista lateral do editor, troca de stance/form e novo Hover Buff Panel.

### 13.24.0 → 13.24.1 Forever

Atualização aplicada em 25/11/2026 após aprovação explícita do usuário e com o WoW fechado. Base original 13.24.0: file ID 9800290; pacote novo 13.24.1: file ID 9807437. Os ZIPs e as árvores originais foram preservados no Workspace externo.

- Mudanças do autor: Floating Loot configurável para loot, rolagens e recompensas (desativado por padrão), popup de detalhes de quests movível pelo título e correção do marcador 3D de quests quando a distância é 0 jardas.
- O autor modificou 57 arquivos e acrescentou `EnhanceQoL/Submodules/LootReplacer.lua` e `LootReplacerDisplay.lua`, sem remoções. Dos 9 arquivos customizados, 7 foram preservados integralmente e apenas as traduções enUS/ptBR precisaram de merge, sem conflitos.
- Mantidos classe/spec por spell, stance/form, reset, traduções, lista lateral de edição independente da postura e filtro de stance no Hover Buff Panel com preview completo. Nenhuma customização foi removida, considerada obsoleta ou duplicada.
- Os 18 módulos e suas junctions foram preservados. Os 1.275 arquivos instalados conferem com os hashes do resultado revisado. Backup verificado dos 1.273 arquivos anteriores: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/EnhanceQoL-13.24.0-mods-backup`.
- CurseForge standalone sincronizado com o file ID 9807437 e reaberto. Como o cliente ainda conhecia a 13.24.0 como última versão, os campos de versão foram atualizados com os metadados oficiais da 13.24.1 e hashes do ZIP, preservando os demais campos do cliente. Backup: `EnhanceQoLUpdater/.upqol/AddonGameInstance.before-13.24.1.json`. As outras entradas foram preservadas; SavedVariables não foram alteradas.
- Retenção: versões 13.24.1, 13.24.0 e 13.23.0 preservadas; nenhuma exclusão necessária ou executada.
- Validações: 29 arquivos Lua compilados em Lua 5.1, 36 TOCs e 410 referências de carregamento conferidos; sem conflitos, novas misturas de finais de linha ou linhas customizadas perdidas. Passaram as regressões de classe/spec, stance/form, cache, reset, lista lateral e Hover Buff Panel. Não houve teste dentro do jogo.
- Git: commit `v13.24.1` em `master`, com push para `origin/master` conforme a proposta. O resultado fica no manifesto da preparação.

Preparação e evidências: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/.upqol/preparation-13.24.0-to-13.24.1-12e4557b8e/`. Prioridades no jogo: Floating Loot se ativado, popup de quests, marcador 3D e continuidade dos filtros do painel/editor.

### 13.24.1 → 13.24.2 Forever

Atualização aplicada em 25/11/2026 após aprovação explícita do usuário e com o WoW fechado. Base original 13.24.1: file ID 9807437; pacote 13.24.2: file ID 9815741. ZIPs, originais e hashes preservados no Workspace externo.

- Mudanças do autor: atalho de buffs para o grupo; ganhos de habilidade, alinhamento e linha de destaque no Floating Loot; informações de sessão, quests e descanso na barra de XP; tamanho e correções do marcador 3D; melhorias em troca, encantamentos, Inspect, Micro Menu e tooltips da barra de pet.
- O autor modificou 66 arquivos e acrescentou 2, sem remoções. Dos 9 arquivos customizados, 7 foram mantidos integralmente e as traduções enUS/ptBR foram mescladas sem conflitos. Nenhuma customização removida, duplicada ou obsoleta.
- Preservados classe/spec por spell, stance/form, reset, traduções, lista lateral independente da postura e filtro de stance no Hover Buff Panel com preview completo.
- Os 18 módulos e junctions foram preservados. Os 1.277 arquivos instalados conferem com o merge aprovado. Backup verificado dos 1.275 anteriores: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/EnhanceQoL-13.24.1-mods-backup`.
- O arquivo vazio `courgette.log`, encontrado fora do Git na raiz do checkout, foi movido intacto e com hash verificado para a pasta de evidências da preparação. O CurseForge foi reaberto usando a pasta do executável como diretório de trabalho, em vez do checkout.
- CurseForge standalone sincronizado com o file ID 9815741 e reaberto. Metadados oficiais e hashes do ZIP foram usados porque o cliente ainda apontava a 13.24.1 como última versão. As outras entradas foram preservadas. Backup: `EnhanceQoLUpdater/.upqol/AddonGameInstance.before-13.24.2.json`. SavedVariables não foram alteradas.
- Retenção: versões 13.24.2, 13.24.1, 13.24.0 e 13.23.0 preservadas, sem exclusões.
- Validações: 37 arquivos Lua compilados em Lua 5.1, 36 TOCs e 412 referências de carregamento conferidos. Sem conflitos, novas misturas de finais de linha ou linhas customizadas perdidas. Passaram as regressões de classe/spec, stance/form, reset, cache, lista lateral e Hover Buff Panel. Não houve teste no WoW.
- Git: commit `v13.24.2` em `master`, com push para `origin/master` conforme a proposta. Resultado no manifesto da preparação.

Preparação e evidências: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLUpdater/.upqol/preparation-13.24.1-to-13.24.2-62a099ad42/`. Prioridades no jogo: buffs de grupo, Floating Loot, opções de XP e marcador 3D, além dos filtros do painel/editor.
