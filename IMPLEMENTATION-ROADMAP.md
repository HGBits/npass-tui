# Roadmap de implementação — npass-tui

Comparação feita em 2026-10-25 entre o código público de [npass_tui](https://github.com/HGBits/npass_tui) (branch `main`) e o [npass-store](https://github.com/HGBits/npass-store) (branch `master`). Este documento descreve o estado observado nos repositórios públicos nesse momento; confirme os contratos da CLI antes de implementar, pois os dois projetos evoluem separadamente.

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

## Pendências

### P0 — Segurança e confiabilidade

- [ ] **Completar a cobertura com mock da CLI e pseudo-terminal (PTY).** O driver determinístico já cobre criação/edição/exclusão, cancelamento e retorno não zero. Ainda faltam caracteres de controle, restauração do terminal após falha/sinal e verificação de que nenhum segredo vai para argv/log/status.
- [ ] **Validar a integração real com terminal e cofre de teste.** Testar manualmente `insert`, `edit`, preview, clipboard e OTP em pelo menos um terminal compatível; não usar o cofre pessoal como fixture.
- [ ] **Revisar limpeza visual de segredos.** Ao sair do preview ou após exibir OTP, limpar/redesenhar a tela quando apropriado e evitar manter conteúdo secreto em status ou mensagens duradouras.
- [ ] **Tratar nomes/caminhos e saída inesperada da CLI de forma robusta.** Não depender de parsing frágil da saída humana; validar nomes e falhas sem esconder erros de descriptografia.
- [x] **Confirmar contrato de listagem da CLI.** A TUI usa `npass ls --flat ID`, conforme o contrato atual documentado em npass-store, em vez do comando legado `tree`.

### P1 — Operações essenciais de gerenciamento

- [x] **Excluir entrada (`npass rm`).** A ação `d` exibe identidade/caminho, alerta sobre anexos de backup e exige digitar `sim`; chama `npass rm` sem `-f`. Testes PTY cobrem confirmação e cancelamento.
- [ ] **Gerar senha (`npass generate`).** Oferecer escolha explícita entre criar/substituir entrada e atualizar só a senha preservando campos, OTP e notas (`--in-place`, quando suportado). Exibir claramente o destino e respeitar a confirmação da CLI.
- [ ] **Renomear/mover entrada (`npass mv`).** Fluxo dedicado para caminho de origem e destino, validação de destino e confirmação. Distinguir movimento dentro da mesma identidade de movimento entre identidades, que recifra para os destinatários de destino.
- [ ] **Criar identidade (`npass init`).** Formulário para ID e destinatários GPG, com validação e confirmação; não misturar administração de identidades com navegação cotidiana.
- [ ] **Melhorar seleção e navegação de caminhos.** Navegação de diretórios, retorno consistente entre telas, estados vazios e preservação do filtro/posição quando fizer sentido.

### P2 — Busca e recursos de autenticação

- [ ] **Busca por caminho mais completa (`npass find`).** Distinguir filtro local da lista de uma busca no store; não confundir com pesquisa do conteúdo secreto.
- [ ] **Ações OTP separadas.** Separar “mostrar código” de “copiar código” (`npass otp clip`); não exibir URI `otpauth://` nem segredo OTP sem ação explícita.
- [ ] **Gerenciamento de PIN (`npass pin`).** Expor escolha inequívoca entre PIN como senha (`--password`) e PIN como campo (`--field`); explicar sobrescrita e não assumir que os modos são intercambiáveis.
- [ ] **Cadastro/atualização de OTP.** Integrar `npass otp insert` somente com fluxo interativo claro e confirmação de sobrescrita.
- [ ] **Frases memoráveis/Diceware.** Adicionar `npass memorable` e `npass diceware`, incluindo as implicações específicas da lista pessoal e da recuperação offline do Diceware.

### P3 — Recursos avançados, depois do núcleo

- [ ] **Backups de recuperação (`npass backup`).** Mostrar que são anexos cifrados e que remoção/movimentação da entrada pode afetá-los.
- [ ] **Histórico Git (`npass log`, `npass loglong`).** Navegar histórico sem sugerir que apagar uma entrada elimina versões antigas do segredo.
- [ ] **Rotação em massa (`npass update`).** Só implementar com seleção/revisão explícita das entradas afetadas e resumo antes de gravar.
- [ ] **Assinatura de identidade (`npass sign`) e extensões.** Exibir apenas recursos realmente disponíveis; extensões são opcionais e podem estar desabilitadas.
- [ ] **Importação e passkeys.** Tratar como integrações avançadas/opcionais, não como pré-requisitos da TUI principal.

### P4 — Qualidade de produto e distribuição

- [ ] **Documentar todos os atalhos e fluxos no README**, incluindo estados vazios, cancelamento, erros, clipboard e requisitos.
- [ ] **Adicionar testes de regressão por funcionalidade** e manter o CI executando-os, não apenas `bash -n`.
- [ ] **Verificar acessibilidade de terminal:** terminfo sem cores, terminais pequenos, redimensionamento, UTF-8/ASCII, teclado sem setas e ausência de clipboard/OTP.
- [ ] **Definir instalação/empacotamento** e dependências opcionais sem exigir extensões para o uso básico.
- [ ] **Adicionar uma matriz de compatibilidade** entre versões do `npass-tui` e contratos de CLI do `npass-store`.

## Ordem recomendada

1. Cobertura de testes PTY/mock e restauração do terminal.
2. Exclusão segura.
3. Geração de senha, com opção de preservar os demais campos.
4. Renomeação/movimentação.
5. Criação de identidade.
6. Melhorias de navegação e busca.
7. OTP/PIN/Diceware e recursos avançados.

## Critério para marcar uma tarefa como concluída

Marque `[x]` somente quando:
1. a implementação estiver no repositório;
2. houver testes relevantes (mock/PTY quando envolver interação);
3. a sintaxe/CI passar;
4. documentação e atalhos estiverem atualizados;
5. riscos de terminal e exposição de segredos tiverem sido revisados.

A lista é um plano de trabalho, não uma afirmação de que todos os comandos do npass devam obrigatoriamente virar telas da TUI. Priorize fluxos frequentes e seguros; transformar cada comando em um menu só produz uma CLI com decoração.
