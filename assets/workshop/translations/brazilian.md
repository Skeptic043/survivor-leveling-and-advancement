# Survivor Leveling & Advancement [B42]

Ganhe pontos ao subir suas habilidades e gaste-os nas habilidades que escolher. SLA adiciona um Nível de Sobrevivente e Pontos de Avanço ao painel normal de habilidades, mantendo a progressão natural. Quer que parte desse progresso sobreviva à sua próxima decisão ruim? A herança opcional permite que seu próximo personagem mantenha uma porcentagem do Nível de Sobrevivente, com novos pontos para gastar.

Suporte a um jogador, multijogador, tela dividida e controle. Sem dependências obrigatórias.

## Como funciona o avanço

A XP obtida em habilidades compatíveis também aumenta seu Nível de Sobrevivente. Cada nível concede um Ponto de Avanço, ou AP. Gaste AP usando os botões **+** ao lado das habilidades. Por padrão, você pode ocupar três espaços de avanço ao mesmo tempo. Praticar uma habilidade avançada libera seus espaços conforme você ganha a XP que pulou. Essa XP também conta para o próximo nível da habilidade.

O último avanço até o máximo efetivo de uma habilidade, normalmente do nível 9 ao 10, é considerado domínio da habilidade. Custa 2 AP e exige 2 Espaços de Avanço livres, depois libera todos os espaços ativos daquela habilidade. Se o limite Global ou Por habilidade for 1, exige apenas 1 espaço livre, mas continua custando 2 AP. O modo Livre não exige espaços e mantém o custo de 2 AP. Uma habilidade em seu máximo efetivo não gera XP de Sobrevivente adicional.

## Mantenha parte do progresso após morrer

Ative a herança do Nível de Sobrevivente e escolha quanto passa ao seu próximo personagem no mesmo mundo. Por exemplo, morrer no Nível de Sobrevivente 20 com herança de 50% dá ao próximo personagem Nível de Sobrevivente 10 e 10 AP para gastar. Os níveis das habilidades antigas não são copiados, permitindo escolher onde usar os pontos herdados. A herança é opcional e vem desativada por padrão.

## Configurações

- **Global:** Todas as habilidades compartilham uma reserva configurável de Espaços de Avanço, com limite padrão de 3 espaços ativos no total.
- **Por habilidade:** Cada habilidade recebe seu próprio limite configurável, com um padrão para habilidades personalizadas compatíveis e ajustes individuais opcionais para as habilidades originais.
- **Livre:** Remove os limites de Espaços de Avanço e as restrições de recuperação de XP.
- Ajuste a velocidade da XP de Sobrevivente sem alterar a XP das habilidades. Escolha se Condicionamento Físico, Força, cada habilidade original e habilidades personalizadas compatíveis contribuem.
- Nas opções de mods, ative marcadores de avanço com mais contraste ou a porcentagem de XP de Sobrevivente do jogador 1 no relógio digital.
- Oferece suporte a todos os idiomas padrão disponíveis nas configurações de idioma do Project Zomboid. Todas as traduções foram feitas inteiramente por IA. Se encontrar algum texto incorreto ou confuso, avise.

**Nota:** Mudar de modo não reinicia o progresso registrado. A XP natural obtida no modo Livre continua abatendo qualquer recuperação azul preservada. Ao voltar para Global ou Por habilidade, apenas o que falta é restaurado.

## Adicionar ou remover SLA

SLA pode ser adicionado ou removido de partidas existentes. As habilidades existentes são preservadas, e o progresso anterior não concede Níveis de Sobrevivente retroativos. Desativar SLA oculta sua interface, mas mantém os níveis de habilidade obtidos com AP. Reativá-lo restaura o estado de SLA e concilia o progresso compatível obtido durante sua ausência. Como em qualquer mudança na lista de mods, recomendo fortemente fazer backup dos mundos que você quer preservar.

## Servidores dedicados e hospedagem

Administradores podem conceder XP de sobrevivente ou níveis inteiros a perfis existentes online e offline. Concessões offline são imediatas. Limpar avanços libera espaços sem devolver AP nem alterar a XP das habilidades. Para personagens offline, a ação fica pendente e pode ser cancelada até que retornem. Alterar um nível pelas estatísticas do jogador limpa o registro daquela habilidade.

SLA usa o salvamento normal de Project Zomboid. Em servidores dedicados e hospedados, ative SaveWorldEveryMinutes e encerre o servidor normalmente.

## Compatibilidade

- **Incompatível: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Sem suporte no momento: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) e [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Esses mods substituem diretamente regras de progressão das quais SLA depende.
- **Depende da ordem de carregamento: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Carregue SLA depois de Detailed Skill Tooltips para acrescentar o texto de recuperação azul às dicas expandidas de DST. Se SLA carregar primeiro, apenas esse texto será substituído. A progressão de Sobrevivente e as dicas dos botões + continuam funcionando.
- **Testados juntos: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) e [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Essa combinação funcionou sem problemas nos testes, mas não é possível garantir compatibilidade com todo mod de interface ou habilidades personalizadas.
- Mods que substituem o processamento de XP, limites ou curvas de habilidades, o painel de habilidades, menus de jogadores ou o relógio digital podem causar conflitos. SLA desativa a integração afetada se seus pontos de integração necessários forem substituídos. Habilidades personalizadas precisam de uma curva de XP utilizável e eventos de XP compatíveis. Alterações diretas de habilidades ou caminhos sem esses eventos não geram XP de sobrevivente.

## Uso de IA

IA foi usada para escrever todo o código deste projeto. O conceito original, a direção do design, os testes, a depuração e as decisões de lançamento são meus. Passei muitas horas testando SLA pessoalmente e resolvendo problemas para garantir que funcione como planejado. Se você prefere não usar mods desenvolvidos com auxílio de IA, entendo e respeito sua escolha.

## Apoio

- Doações no [Ko-fi](https://ko-fi.com/skeptic043) são opcionais. Nenhuma função do mod exige pagamento.

## Informações do mod

- Desenvolvido/testado na versão: 42.20.4
- Dependências obrigatórias: Nenhuma
- Licença: MIT
- [Código-fonte e relatos de problemas](https://github.com/Skeptic043/survivor-leveling-and-advancement)
