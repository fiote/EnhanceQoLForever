# Registro do CurseForge

Leia esta referência quando a proposta incluir sincronizar a versão instalada no aplicativo. Não é necessário alterar o registro para fazer o inventário ou preparar um merge.

Nesta máquina, o cliente é standalone. O registro observado para o fluxo DaylightUI é `%APPDATA%/CurseForge/agent/GameInstances/AddonGameInstance.json`, e o launcher é `%LOCALAPPDATA%/Programs/CurseForge Windows/CurseForge.exe`. Confira a existência e a estrutura atuais; não assuma que os caminhos Overwolf sejam equivalentes. Se outro cliente estiver em uso, identifique seu registro real antes de escrever.

1. Leia o registro e selecione a instalação cuja pasta `AddOns` resolve para a instalação configurada no inventário. Dentro dela, identifique o projeto **1076354**. A mesma conta pode ter várias instalações do WoW; o project ID sozinho não identifica o registro correto.
2. Confira a identidade do arquivo instalado contra o manifesto (file ID, nome, versão e flavor) e a consistência dos campos do registro. Se já apontar para o arquivo aplicado, preserve os bytes. Se mudou desde a preparação, reavalie a proposta.
3. Só após a instalação aprovada e verificada, e com a alteração do JSON e o fechamento/reabertura do aplicativo cobertos pela aprovação, feche o cliente. Não faça encerramento forçado se isso não foi autorizado. Preserve as outras instâncias e addons.
4. Registre o hash e faça backup do JSON em um arquivo novo. Atualize os campos que representem a versão/pacote usando os metadados exatos do arquivo baixado. Não invente um esquema nem regrave entradas alheias. Preserve campos desconhecidos; confira que o arquivo não mudou desde a leitura e grave atomicamente.
5. Reabra o cliente se isso fizer parte da proposta. Se `ELECTRON_RUN_AS_NODE` estiver presente no ambiente da sessão, retire-o somente do ambiente do processo filho ao iniciar o launcher Electron. Não altere o ambiente global. Defina o diretório de trabalho como a pasta do executável do CurseForge, em vez de herdar o checkout Git, para evitar logs do aplicativo dentro do repositório.
6. Releia o registro e confirme a entrada do EnhanceQoL e a preservação das demais. Guarde caminho do backup e resultado no manifesto e no relatório final.

Na ausência de acesso ao registro ou se sua estrutura não for reconhecida, preserve a instalação aplicada e relate a sincronização como pendente; não afirme que o aplicativo foi atualizado.
