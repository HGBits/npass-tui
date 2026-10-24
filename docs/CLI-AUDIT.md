# Auditoria da CLI do npass para o npass-tui

Status: **Fase 1 concluída**  
Data da auditoria: 2026-10-24

## 1. Fonte de verdade e escopo

A fonte autoritativa desta auditoria é o arquivo `projeto(2).zip` reenviado pelo usuário nesta conversa. **Esse snapshot prevalece sobre o GitHub público, que o usuário identificou como antigo.** Não inferir contratos atuais a partir do repositório público nem usar diferenças com ele como defeitos da versão atual.

O ZIP contém 91 entradas, incluindo README, `lib/`, `extensions/`, `tests/`, documentação de manpages e o helper Rust de passkeys. O README incluído identifica o projeto como npass 2.5. O executável `bin/npass` é gerado por `build.sh`; não é fonte primária e não veio no ZIP como artefato de referência.

Escopo desta fase: mapear os contratos públicos relevantes para a TUI, registrar as operações disponíveis, identificar comportamentos perigosos e estabelecer a ordem segura de implementação. Nenhuma operação de cofre real foi executada.

## 2. Estrutura do programa

| Arquivo | Responsabilidade observada |
|---|---|
| `lib/00-main.bash` | Despacho dos comandos e aliases |
| `lib/01-common.bash` | Erros, caminhos, temporários, GPG e limpeza |
| `lib/02-identity.bash` | Identidades, destinatários, mapa lógico e nomes físicos |
| `lib/03-store.bash` | Inserção, leitura crua interna, edição, remoção, movimentação, geração e busca |
| `lib/04-clipboard.bash` | `clip` e `get` |
| `lib/05-otp.bash` | Código OTP, URI, cadastro, cópia e validação |
| `lib/06-update.bash` | Rotação em massa |
| `lib/08-pin.bash` | PIN como senha ou campo independente |
| `lib/07-git.bash` | Histórico e commits |
| `lib/10-signing.bash` | Assinatura de identidade |
| `lib/11-extensions.bash` | Extensões assinadas |
| `lib/12-diceware.bash` | Diceware e frases memoráveis |
| `lib/13-backup.bash` | Anexos cifrados de senhas de recuperação |
| `lib/14-entry.bash` | Parser e serializador único do formato md1 |
| `lib/15-tree.bash` | Árvore de caminhos e saída plana para máquinas |
| `lib/16-view.bash` | Comando público `show`, renderização Markdown e links de navegação |
| `lib/17-open.bash` | Abertura de links `npass://` com confirmação |
| `lib/18-help.bash` | Ajuda por categoria e seção |

Regra arquitetural importante: a TUI deve chamar a CLI pública e não depender de funções Bash internas, do mapa cifrado ou dos nomes físicos de blobs. O executável é construído a partir de `lib/` com `bash build.sh` (o bit executável de `build.sh` não estava definido no ZIP extraído).

## 3. Comandos públicos e contratos confirmados

### Identidades e navegação

| Operação | Contrato atual | Implicação para a TUI |
|---|---|---|
| Listar identidades | `npass identities` ou `npass ids` | A saída é texto de apresentação, com nome e contagem de arquivos blob. Não tratá-la como formato estruturado estável nem presumir que a contagem seja só logins: anexos também são blobs. |
| Criar identidade | `npass init [--sign[=KEYID]] ID RECIPIENT...` | Administração separada da navegação normal; requer destinatários GPG. |
| Listar caminhos | `npass tree --flat ID [DIR]` | **Interface de máquina documentada:** um caminho lógico por linha, sem decoração. Preferir essa forma para alimentar a lista. |
| Árvore humana | `npass tree ID [DIR]` | Inclui pastas inferidas, marcadores `[backup]` e desenho dependente de locale/TTY; não fazer parsing dessa apresentação se `--flat` atende. |
| Comando antigo de listagem | `ls`/`list` | Explicitamente recusado: a mensagem orienta para `tree`. Não usar `npass ls`. |
| Procurar caminhos | `npass find ID PADRÃO` | Busca textual nos caminhos lógicos; não confundir com pesquisa de conteúdo. |
| Procurar conteúdo | `npass grep ID [OPÇÕES-GREP] PADRÃO` | Decifra entradas e pode imprimir segredos. Não executar implicitamente nem despejar resultados na tela da TUI. |

### Ler, copiar e exibir

| Operação | Contrato atual | Implicação para a TUI |
|---|---|---|
| Mostrar entrada | `npass show [--raw|--render] ID DIR/PASS` | Em TTY, o modo automático renderiza com `glow`; em pipe, a saída padrão é md1 cru. |
| Leitura bruta | `npass show --raw ID DIR/PASS` | A opção existe no snapshot atual e é adequada ao preview programático. A saída ainda deve ser sanitizada antes de renderizar numa TUI. |
| Renderização forçada | `npass show --render ID DIR/PASS` | Renderiza mesmo em pipe; não é o modo indicado para parsing. |
| Copiar senha/campo | `npass clip [CAMPO] ID DIR/PASS` | Sem campo, copia a senha; `all` copia o documento inteiro; campos como `login`, `email` e `pin` são suportados pelo parser md1. |
| Obter valor no stdout | `npass get [--exact] [CAMPO] ID DIR/PASS` | Imprime o valor em vez de copiá-lo. `--exact` evita correspondência por prefixo. Tratar stdout como secreto. |

### Escrita e manutenção de entradas

| Operação | Contrato atual | Risco/decisão de UX |
|---|---|---|
| Inserção interativa | `npass insert [-f] ID DIR/PASS` (alias `add`) | Solicita o segredo duas vezes sem eco. Se já existir, pergunta antes de sobrescrever; `-f` elimina a confirmação. A TUI nunca deve passar `-f` silenciosamente. |
| Inserção em lote | `npass insert --batch [-f] ID` | Lê pares `CAMINHO NUL DOCUMENTO-MD1 NUL` do stdin; conteúdo pode ter várias linhas. Recusa conteúdo fora de md1 (exceto marcador de anexo de backup), pula existentes sem `-f` e faz um commit ao fim. Não montar segredos em argv. |
| Editar | `npass edit ID DIR/PASS` | Abre `$EDITOR` com um temporário criado pela infraestrutura do npass; entrada existente precisa ser md1 válido. Caminho inexistente abre um modelo md1 vazio. Só salva se mudou e passou validação. |
| Remover | `npass rm [-f] ID DIR/PASS` | Confirma por padrão. Também remove anexos de backup reconhecidos; falha se não conseguir inspecionar anexos com segurança. A confirmação da TUI deve deixar esse efeito explícito. |
| Mover/renomear na mesma identidade | `npass mv ID ORIGEM DESTINO` | Altera o mapa lógico; o blob cifrado da entrada permanece intacto. Anexos de backup acompanham a mudança de prefixo. |
| Mover entre identidades | `npass mv ID ORIGEM ID2 DESTINO` | Decifra e cifra novamente para os destinatários da identidade de destino; move anexos de backup também. Deve ser uma ação distinta e claramente confirmada. |
| Gerar senha | `npass generate [-n|-c|-f] [--in-place] ID DIR/PASS [TAMANHO]` (alias `gen`) | Padrão 25 caracteres, salvo configuração. Sem `--in-place`, cria ou substitui a entrada inteira com uma nova entrada contendo só a senha. Com `--in-place`, troca a senha e preserva campos/OTP/notas, se a entrada existir e for md1. `-c` copia em vez de imprimir; `-f` pula confirmação de sobrescrita. |
| Atualização em massa | `npass update [OPÇÕES] ID PADRÃO...` | Pode rotacionar senhas, editar entradas, copiar senhas antigas ou substituir documentos md1. Padrões são caminhos exatos ou prefixos terminados em `/`, não glob de shell. Adiar integração até existir fluxo de revisão e resumo. |

### OTP, PIN e senhas de recuperação

| Operação | Contrato atual | Implicação para a TUI |
|---|---|---|
| Gerar OTP | `npass otp ID DIR/PASS` | Mostra o código TOTP/HOTP. O código é secreto temporário; não o inserir em logs/status persistentes. |
| Copiar OTP | `npass otp clip ID DIR/PASS` | Preferível quando a intenção é copiar sem expor o código na tela. A TUI deve separar “mostrar” e “copiar”. |
| Cadastrar OTP | `npass otp insert [-f] [-s --secret] [-i ISSUER] [-a CONTA] ID DIR/PASS` | Interativo; permite informar URI ou gerar URI a partir de segredo. Sobrescrita do OTP existente pede confirmação salvo `-f`. |
| URI OTP | `npass otp uri [-c|-q] ID DIR/PASS` | A URI contém o segredo OTP. Não mostrar, copiar ou registrar sem ação explícita. `-q` apresenta QR; requer `qrencode`. |
| Validar URI | `npass otp validate URI` | Valida URI sem acessar o store. |
| Gerar PIN | `npass pin (--password|--field) [-c] [-f] [--in-place] ID DIR/PASS [DÍGITOS]` | O modo é obrigatório. `--password` define a senha da entrada; `--field` altera/adiciona o campo `pin:` numa entrada existente. Não presumir que PIN sempre substitui a senha. |
| Criar backup de recuperação | `npass backup [-f] -n N ID DIR/PASS` | N de 1 a 50, senha(s) digitadas ocultas e confirmadas. Cria dois anexos cifrados; a TUI precisa alertar que remover/mover a entrada também afeta anexos. |

### Administração e recursos avançados

- `npass sign ID [KEYID]`: assina/reassina a configuração de destinatários da identidade.
- `npass git ARGS...`, `npass log`, `npass loglong`: histórico do store. Todo store é inicializado como repositório Git; escritas fazem commits automáticos.
- `npass diceware` e `npass memorable`: geração de frases.
- `npass open [--here] [--pause] npass://ID/CAMINHO`: somente exibe após confirmação antes de decifrar; rejeita URLs/caminhos inválidos. Não é necessário à navegação básica da TUI.
- `npass extension sign|list|install`: gerenciamento de extensões assinadas. `import`, `audit`, `passkey`, `clip-x11` e `wclip` são extensões, não operações nativas que a TUI deva presumir disponíveis.
- `migrate` e `migrate-secrets`: encaminhamento antigo removido; a mensagem aponta para a extensão de importação. Não basear a TUI nesses comandos.
- A ajuda é organizada por categoria: `npass help`, `npass help entradas`, `npass help gerar`, `npass help otp`. Nem todo comando oferece `--help` próprio.

## 4. Formato dos dados: md1

O conteúdo de cada entrada é um documento com marcador obrigatório na primeira linha:

```markdown
<!-- npass:md1 -->
## Senha
senha exata, sem trim

## Campos
- login: usuario
- url: https://exemplo

## OTP
otpauth://...

## Notas
texto livre
```

Regras críticas:
- `lib/14-entry.bash` é o parser/serializador canônico. Outros módulos devem usar suas funções, não reimplementar parsing de senha/campos/OTP.
- A senha é a linha imediatamente depois de `## Senha`; espaços nas pontas e caracteres como `#` devem ser preservados.
- As seções opcionais seguem a ordem Campos, OTP, Notas. Notas ocupa o restante do documento.
- Conteúdo sem marcador md1 ou com estrutura inválida deve ser recusado para edição/alteração, não reinterpretado como formato antigo.
- `show --raw` devolve o documento md1; `get` devolve um campo/valor. Não confundir as duas saídas.
- A TUI deve evitar converter md1 para uma estrutura própria que perca linhas desconhecidas, notas ou valores especiais. Para leitura, manter o conteúdo cru; para edição, delegar ao `npass edit`.

## 5. Armazenamento e efeitos colaterais

- Uma identidade tem `.gpg-id`, mapa cifrado `.map.gpg` e diretório `blobs/`; caminhos lógicos não são nomes físicos dos blobs.
- O mapa associa caminho lógico a blob opaco. Renomear dentro da identidade altera o mapa, não o ciphertext; mover entre identidades exige recifrar.
- O store usa GPG; o clipboard padrão é Wayland. Git é integrado e commits são feitos após operações de escrita.
- `rm`, `mv` e `update` reconhecem anexos de backup por nome e marcador de conteúdo, e fazem operações em cascata onde aplicável.
- O comando `show` público pode renderizar com `glow`; a TUI deve chamar `--raw` para parsing/previews previsíveis.
- Não usar `ls/list`, caminhos físicos de blob, o mapa cifrado ou detalhes internos como interface da TUI.

## 6. Requisitos de segurança e integração

1. **TTY ao chamar editor:** guardar o modo original, desativar o modo raw/restore do terminal da TUI antes de chamar `npass edit`, deixar stdin/stdout/stderr ligados ao terminal e reinstalar o modo da TUI após o retorno, inclusive em falhas/sinais.
2. **Confirmações destrutivas:** mostrar identidade e caminho completos antes de `rm`, sobrescrita ou `mv`; deixar claro que anexos de backup acompanham remoção/movimentação. Cancelamento deve não chamar o comando.
3. **Sem `-f` implícito:** `-f`/ `--force` remove uma barreira de confirmação em vários comandos. Só usar após uma confirmação explícita e inequívoca, ou preferir o modo interativo padrão.
4. **Sanitização de terminal:** caminhos lógicos e conteúdo podem conter bytes/texto que alteram a tela. Filtrar sequências ANSI/OSC e controles antes de renderizar na TUI; nunca permitir que o conteúdo de uma entrada controle o terminal.
5. **Segredos em memória e saída:** não enviar senha/URI OTP a logs, mensagens de status, argumentos de processo ou arquivos temporários da TUI. Não despejar `grep`/saídas cruas em logs.
6. **Exit status:** respeitar falhas da CLI. Não tratar saída vazia como sucesso automático nem engolir falhas de descriptografia, parser ou validação.
7. **Identidades:** não interpretar a contagem textual de `identities` como API estruturada. Se precisar de robustez adicional, validar nomes e tratar erros de parsing sem assumir formato futuro.
8. **Testes:** criar testes da TUI com um mock do executável `npass`, verificar argv/ordem/cancelamentos e usar fixtures temporárias. Não executar testes destrutivos contra o cofre real.

## 7. Ajustes obrigatórios no plano da TUI

Ordem recomendada após a auditoria:

1. Verificar a implementação atual da TUI contra os contratos `tree --flat` e `show --raw`; adicionar testes de parsing e sanitização.
2. Criar entrada usando `npass insert`, respeitando a interação oculta e a confirmação nativa de sobrescrita.
3. Integrar `npass edit` com restauração completa do terminal.
4. Implementar exclusão com confirmação que mencione anexos de backup.
5. Implementar geração de senha com escolha explícita entre nova entrada/substituição e `--in-place`.
6. Implementar renomeação e movimento entre identidades como fluxos distintos, com validação de destino e confirmação.
7. Depois, adicionar busca por caminhos, ações OTP e PIN. Deixar `update`, `grep`, importação e administração para fases posteriores.

## 8. Validação realizada e limitações

Executado sobre o snapshot reenviado:
- Inspeção do README, do despacho principal, dos módulos funcionais relevantes, da ajuda e dos testes correspondentes.
- `bash -n lib/*.bash` passou.
- `bash -n build.sh install.sh extensions/npass-import extensions/npass-audit` passou.
- O build passou com `bash build.sh`, gerando `bin/npass` no diretório temporário de auditoria.
- Smoke tests do binário gerado: `npass help` e `npass tree --help` retornaram 0; `npass show --help` retornou 1 com `opção desconhecida`, confirmando que `show` não oferece `--help` próprio neste snapshot.
- O comando `bats` não está instalado neste ambiente; por isso a suíte de 27 arquivos Bats **não foi executada**. Não declarar a suíte aprovada.
- Não houve integração interativa com um cofre real nem teste em terminal PTY nesta fase.
- O ZIP declara versão 2.5 no README, mas não fornece uma referência Git imutável (commit/hash) que permita identificar seu commit de origem. Esta nota documenta o snapshot enviado, não uma afirmação de que o branch público atual seja idêntico.

## 9. Decisão de encerramento da fase

**Fase 1 encerrada:** os contratos públicos relevantes para a TUI foram mapeados a partir do snapshot correto, as operações e efeitos colaterais estão documentados, e os riscos de terminal/segredos foram convertidos em requisitos de implementação.

Não foram implementadas operações novas da TUI nesta fase. A próxima fase deve começar pela revisão da TUI atual e pelos testes de mock, depois seguir com `insert` e `edit`. O GitHub público do npass continua sendo referência histórica/secundária enquanto estiver divergente do ZIP fornecido.
