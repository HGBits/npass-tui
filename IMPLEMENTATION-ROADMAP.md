# Roadmap de implementação — npass-tui

Comparação feita em 2026-10-25 entre o código público de [npass_tui](https://github.com/HGBits/npass_tui) (branch `master`) e o [npass-store](https://github.com/HGBits/npass-store) (branch `master`, versão 2.8). A CLI atual usa `npass ls --flat ID [DIR]`; `tree` é legado e falha com orientação para `ls`. O contrato divergente de `tree --flat` documentado em `docs/CLI-AUDIT.md` pertence ao snapshot histórico npass 2.5, não à CLI atual.

## Estado atual observado

A TUI já oferece:
- [x] Verificação de dependências básicas (`tput`, binário `npass`) e exigência de terminal interativo.
- [x] Navegação entre identidades e lista de caminhos/entradas.
- [x] Preview de entrada com rolagem e sanitização de sequências de controle.
- [x] Filtro/pesquisa simples sobre os caminhos listados.
- [x] Criar entrada com `npass insert ID CAMINHO`, sem `-f` implícito; caminho vazio cancela.
- [x] Editar entrada selecionada com `npass edit ID CAMINHO`.
- [x] Copiar senha/campo padrão usando `npass clip ID CAMINHO`.
- [x] Solicitar OTP pela CLI (`npass otp`).
- [x] Devolver o terminal à CLI para operações interativas e reativar o modo da TUI após o retorno.
- [x] Testes Bats para criação, edição e exclusão com driver PTY determinístico; CI valida sintaxe Bash/Python e executa os seis cenários.

## Política de implementação e testes

**Cada função ou funcionalidade nova ou modificada deve vir acompanhada de testes comportamentais que verifiquem se a TUI respeita o fluxo planejado.** Os testes fazem parte da entrega, não são uma etapa opcional para “quando der tempo”.

Para cada mudança, cubra o que for aplicável:
- Caminho de sucesso e resultado/estado visível esperado na TUI.
- Cancelamento, entradas inválidas e limites do fluxo.
- Falha da CLI, status de saída e saída inesperada, garantindo que a interface não anuncie sucesso falso.
- Argumentos exatos enviados ao mock da CLI, incluindo identidade e caminho, e ausência de flags perigosas implícitas.
- Fluxos de teclado, confirmação, troca de tela e restauração de terminal usando Bats/PTY.
- Sanitização de saída não confiável, ausência de segredos em argv/log/status e limpeza visual para operações sensíveis.
- Regressões reproduzíveis: adicionar um teste que demonstre a falha antes da correção e passe depois dela.

Use mocks/fixtures isolados, nunca o cofre pessoal. Inclua os testes novos no CI. Uma verificação de sintaxe, sozinha, não comprova o comportamento da TUI. Não marque uma tarefa como concluída enquanto os testes comportamentais relevantes estiverem ausentes ou falhando.

## Pendências

### P0 — Segurança e confiabilidade

- [ ] **Completar a cobertura com mock da CLI e pseudo-terminal (PTY).** O driver determinístico cobre criação/edição/exclusão, cancelamento, retorno não zero, saída maliciosa com sequências OSC/CSI tanto no preview quanto em caminhos listados, restauração após `SIGINT`, `SIGTERM`, `SIGHUP` e saída normal, e após falha de comando interativo, entrega do modo normal do terminal à CLI e retorno ao modo TUI. Testes também verificam que falhas de listagem, preview, clipboard e OTP não imprimem a saída arbitrária da CLI no status; o OTP de fixture não aparece no log de argumentos nem no status, e a tela de preview é limpa ao sair. Ainda falta ampliar a cobertura de fluxos sensíveis e falhas da CLI, além de validar a integração manual com terminal e cofre de teste.
- [ ] **Validar a integração real com terminal e cofre de teste.** Testar manualmente `insert`, `edit`, preview, clipboard e OTP em pelo menos um terminal compatível; não usar o cofre pessoal como fixture.
- [ ] **Revisar limpeza visual de segredos.** Ao sair do preview ou após exibir OTP, limpar/redesenhar a tela quando apropriado e evitar manter conteúdo secreto em status ou mensagens duradouras.
- [ ] **Tratar nomes/caminhos e saída inesperada da CLI de forma robusta.** Não depender de parsing frágil da saída humana; validar nomes e falhas sem esconder erros de descriptografia.
- [x] **Confirmar contrato de listagem da CLI.** A TUI usa `npass ls --flat ID`, conforme o contrato atual documentado em npass-store, em vez do comando legado `tree`.

### P1 — Operações essenciais de gerenciamento

- [x] **Excluir entrada (`npass rm`).** A ação `d` exibe identidade/caminho, alerta sobre anexos de backup e exige digitar `sim`; chama `npass rm` sem `-f`. Testes PTY cobrem confirmação e cancelamento.
- [ ] **Gerar senha (`npass generate`).** Oferecer escolha explícita entre criar/substituir entrada e atualizar só a senha preservando campos, OTP e notas (`--in-place`, quando suportado). Exibir claramente o destino e respeitar a confirmação da CLI. Criar testes comportamentais para sucesso, cancelamento, destino existente e falhas da CLI.
- [ ] **Renomear/mover entrada (`npass mv`).** Fluxo dedicado para caminho de origem e destino, validação de destino e confirmação. Distinguir movimento dentro da mesma identidade de movimento entre identidades, que recifra para os destinatários de destino. Testar ambos os tipos de movimento, cancelamento e falhas.
- [ ] **Criar identidade (`npass init`).** Formulário para ID e destinatários GPG, com validação e confirmação; não misturar administração de identidades com navegação cotidiana. Testar entradas inválidas, cancelamento e erro da CLI.
- [ ] **Melhorar seleção e navegação de caminhos.** Navegação de diretórios, retorno consistente entre telas, estados vazios e preservação do filtro/posição quando fizer sentido. Testar teclado e transições de estado via PTY.

### P2 — Busca e recursos de autenticação

- [ ] **Busca por caminho mais completa (`npass find`).** Distinguir filtro local da lista de uma busca no store; não confundir com pesquisa do conteúdo secreto. Testar resultados, nenhum resultado, cancelamento e falha.
- [ ] **Ações OTP separadas.** Separar “mostrar código” de “copiar código” (`npass otp clip`); não exibir URI `otpauth://` nem segredo OTP sem ação explícita. Testar seleção da ação, falha e limpeza de tela.
- [ ] **Gerenciamento de PIN (`npass pin`).** Expor escolha inequívoca entre PIN como senha (`--password`) e PIN como campo (`--field`); explicar sobrescrita e não assumir que os modos são intercambiáveis. Testar seleção de modo, confirmação e falhas.
- [ ] **Cadastro/atualização de OTP.** Integrar `npass otp insert` somente com fluxo interativo claro e confirmação de sobrescrita. Testar cancelamento e não vazamento do segredo.
- [ ] **Frases memoráveis/Diceware.** Adicionar `npass memorable` e `npass diceware`, incluindo as implicações específicas da lista pessoal e da recuperação offline do Diceware. Testar argumentos, erros e apresentação dos resultados.

### P3 — Recursos avançados, depois do núcleo

- [ ] **Backups de recuperação (`npass backup`).** Mostrar que são anexos cifrados e que remoção/movimentação da entrada pode afetá-los. Testar confirmações e erros.
- [ ] **Histórico Git (`npass log`, `npass loglong`).** Navegar histórico sem sugerir que apagar uma entrada elimina versões antigas do segredo. Testar estados vazios, navegação e falhas.
- [ ] **Rotação em massa (`npass update`).** Só implementar com seleção/revisão explícita das entradas afetadas e resumo antes de gravar. Testar seleção, cancelamento e confirmação.
- [ ] **Assinatura de identidade (`npass sign`) e extensões.** Exibir apenas recursos realmente disponíveis; extensões são opcionais e podem estar desabilitadas. Testar indisponibilidade e erros.
- [ ] **Importação e passkeys.** Tratar como integrações avançadas/opcionais, não como pré-requisitos da TUI principal. Testar importação inválida, cancelamento e falhas sem alterar dados indevidamente.

### P4 — Qualidade de produto e distribuição

- [ ] **Documentar todos os atalhos e fluxos no README**, incluindo estados vazios, cancelamento, erros, clipboard e requisitos.
- [ ] **Manter testes de regressão por funcionalidade no CI.** Cada novo comportamento ou correção deve adicionar/atualizar testes comportamentais de TUI, não apenas executar `bash -n`.
- [ ] **Verificar acessibilidade de terminal:** terminfo sem cores, terminais pequenos, redimensionamento, UTF-8/ASCII, teclado sem setas e ausência de clipboard/OTP.
- [ ] **Definir instalação/empacotamento** e dependências opcionais sem exigir extensões para o uso básico.
- [ ] **Adicionar uma matriz de compatibilidade** entre versões do `npass-tui` e contratos de CLI do `npass-store`.

## Ordem recomendada

1. Cobertura de testes PTY/mock e restauração do terminal.
2. Geração de senha, com opção de preservar os demais campos.
3. Renomeação/movimentação.
4. Criação de identidade.
5. Melhorias de navegação e busca.
6. OTP/PIN/Diceware e recursos avançados.

## Critério para marcar uma tarefa como concluída

Marque `[x]` somente quando:
1. a implementação estiver no repositório;
2. houver testes comportamentais relevantes, incluindo mock/PTY quando envolver interação;
3. os testes relevantes e a suíte completa passarem, e o CI estiver verde quando disponível;
4. documentação e atalhos estiverem atualizados;
5. riscos de terminal e exposição de segredos tiverem sido revisados.

A lista é um plano de trabalho, não uma afirmação de que todos os comandos do npass devam obrigatoriamente virar telas da TUI. Priorize fluxos frequentes e seguros; transformar cada comando em um menu só produz uma CLI com decoração.
