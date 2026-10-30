# npass-tui

Interface de terminal em **Bash** para o [`npass`](https://github.com/HGBits/npass-store). A TUI é uma camada de apresentação: armazenamento, criptografia, descriptografia, clipboard e OTP continuam sendo responsabilidade do `npass`.

## Requisitos

- Bash 4.3+
- `tput` e `stty` (normalmente fornecidos por ncurses/coreutils/util-linux, conforme a distribuição)
- `npass-store` **2.8** instalado e configurado conforme a documentação do projeto (versão-alvo; a TUI aborta se a versão for incompatível — `NPASS_TUI_SKIP_VERSION_CHECK=1` ignora a checagem)
- Terminal interativo com suporte a terminfo, no mínimo 40 colunas × 10 linhas (abaixo disso a TUI mostra um aviso e só aceita sair)

Não depende de Python, `dialog`, `fzf` ou `gum`.

## Estrutura

O código-fonte fica em `lib/*.bash`. `build.sh` concatena os arquivos, em ordem, no
executável único `bin/npass-tui` (no `.gitignore`), do mesmo modo que o npass-store gera `bin/npass`,
e assina o resultado com GPG (`bin/npass-tui.asc`).
O binário gerado não procura `lib/` em tempo de execução: pode ser copiado para qualquer lugar.

```
lib/00-core.bash    # estado, traps, modo do terminal, sanitização
lib/01-input.bash   # teclado → tokens lógicos
lib/02-backend.bash # contrato com a CLI npass (versão, identidades, caminhos)
lib/03-render.bash  # layout, renderização incremental (paint), painéis Explorer/Contexto
lib/04-actions.bash # ações do usuário (clip, otp, insert, edit, rm, filtro)
lib/99-main.bash    # checagens de ambiente, loop principal e ponto de entrada (sempre por último)
build.sh            # lib/*.bash -> bin/npass-tui + bin/npass-tui.asc (assinatura GPG)
```

Não há `install.sh`: o build gera e assina o binário, e instalar é copiá-lo.

## Build e assinatura

```sh
./build.sh                # gera e assina com a chave padrão
./build.sh --key=ID       # assina com a chave ID (fingerprint ou e-mail)
./build.sh --no-sign      # só gera o binário (testes, CI)
```

Chave usada, em ordem: `--key`, `NPASS_TUI_SIGN_KEY`, `git config user.signingkey`, chave secreta padrão do gpg.
O build verifica a própria assinatura e falha, sem deixar `.asc`, se não conseguir assinar. Verificar:

```sh
gpg --verify bin/npass-tui.asc bin/npass-tui
```

## Instalar

```sh
./build.sh
sudo install -Dm755 bin/npass-tui /usr/bin/npass-tui                # global
install -Dm755 bin/npass-tui "$HOME/.local/bin/npass-tui"           # só para o seu usuário
```

Remover: apague o arquivo instalado (`sudo rm /usr/bin/npass-tui` ou `rm ~/.local/bin/npass-tui`).

## Executar sem instalar

```sh
./build.sh --no-sign
./bin/npass-tui
```

Se `npass` não estiver no `PATH`, informe o caminho:

```sh
NPASS_BIN="$HOME/.local/bin/npass" ./bin/npass-tui
```

## Tela

```
 npass-tui  COFRE / personal
────────────────────────────────────────┬─────────────────────────────
 ENTRADAS  3/12                         │ CONTEXTO
 > example/login                        │ login
   second/entry                         │ Pasta:       example
                                        │ Posição:     3 de 12
────────────────────────────────────────┴─────────────────────────────
 mensagem transitória (status)
 ↑↓ Navegar  Enter Abrir  / Filtrar  A Criar  E Editar  D Excluir ...
```

- **Explorer** (esquerda, ~40%): identidades ou entradas, com posição/total e filtro.
- **Contexto** (direita): resumo da seleção; no preview, o conteúdo da entrada.
- **Status**: só mensagens transitórias; some na tecla seguinte.
- **Atalhos**: só os da tela atual. Em terminal estreito caem primeiro os menos importantes.
- Com menos de 49 colunas o layout é compacto: um painel por vez.
- A TUI não define cores: usa bold, dim e reverse e herda o tema do terminal.
- Locale sem UTF-8, ou `NPASS_TUI_ASCII=1`, troca bordas e símbolos por ASCII. Caracteres de largura dupla (CJK, emoji) em caminhos não têm a largura calculada e podem desalinhar a linha.

## Controles

- `↑` / `↓` ou `j` / `k`: navegar (no preview revelado, rolar)
- `Enter`: abrir identidade; abrir entrada (executa `npass show --raw`, mas o conteúdo abre **oculto**)
- `v`: revelar/ocultar o conteúdo no preview
- `/`: filtrar caminhos; filtro vazio mostra tudo
- `c`: copiar senha via `npass clip`
- `o`: consultar OTP via `npass otp`; qualquer tecla volta
- `a`: criar entrada, informando o caminho; o próprio `npass insert` solicita a senha duas vezes sem eco e confirma antes de sobrescrever
- `e`: editar a entrada selecionada com `npass edit` e o editor definido em `$EDITOR`
- `d`: excluir a entrada selecionada; exige digitar `sim`, avisa sobre anexos de backup e mantém a confirmação nativa do `npass rm`
- `Esc`: voltar
- `q`: voltar ou sair

## Segurança e escopo

- Identidades são obtidas por `npass identities`; caminhos por `npass ls --flat ID`.
- O conteúdo é obtido apenas com `Enter` numa entrada, via `npass show --raw ID CAMINHO`; navegar, filtrar e o painel de Contexto nunca o leem. O preview abre oculto e só `v` o desenha; ao sair do preview as linhas são descartadas.
- A TUI não grava segredos em arquivos temporários nem implementa o formato de armazenamento do npass.
- A TUI delega criação, edição e exclusão à CLI do `npass`; não implementa armazenamento nem parsing de escrita próprio. Movimentação e geração ainda não fazem parte da interface.
- O conteúdo decifrado fica na memória do processo enquanto o preview está aberto, mesmo oculto (o bash não permite zerá-la), e pode ser capturado por gravação de terminal ou visto por alguém com acesso à tela. Use em uma sessão confiável.

## Estado

Navegação por identidades e caminhos em Split View com renderização incremental, preview protegido com scroll, filtro simples, clipboard e OTP. A implementação ainda precisa ser validada manualmente contra um cofre real em diferentes terminais.
