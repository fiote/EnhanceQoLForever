# EnhanceQoL Forever: contexto e customizações locais

Registro inicial da skill em 24/11/2026. Confira o estado atual em disco antes de usar estas informações para uma atualização.

## Instalação

- Checkout ativo: `C:/Program Files (x86)/World of Warcraft Workspace/EnhanceQoLRepo`.
- Remoto: `https://github.com/fiote/EnhanceQoLForever`, branch observada `master`.
- HEAD observado ao criar a skill: `82e0a601169b6454a4d84914b3fa3c961d00c8c2`, sincronizado com `origin/master`, sem alterações pendentes.
- TOC carregado no cliente Forever: `EnhanceQoL/EnhanceQoL_Camelot.toc`, versão **13.23.0**, interface **16001**, `X-EQOL-Flavor: forever`.
- Projeto CurseForge indicado pelo TOC: **1076354**. A identidade e o nome exato dos ZIPs/base devem ser conferidos na atualização; ainda não houve download ou atualização por esta skill.
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

Este documento não é um inventário completo do commit inicial. Antes de atualizar, compare todos os módulos com o ZIP original **13.23.0 Forever** ou com a base que corresponda à versão efetivamente instalada. Inspecione também TOCs/XML Camelot, compatibilidade de APIs, grupos de talentos e os demais componentes `*_Camelot`. Não apague uma adaptação só porque ela não aparece na lista acima.

O nome de um arquivo `_Camelot` por si só não prova que seja uma customização nossa: ele pode vir do autor. Registre a origem com base na comparação real.

## Histórico de atualizações pela skill

Nenhuma atualização executada na criação da skill. Acrescente entradas somente depois de operações reais, com versão, origem da base, decisões, backups e validações observadas.
