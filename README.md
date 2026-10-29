# npass-tui

Interface de terminal em **Bash** para o [`npass`](https://github.com/HGBits/npass). A TUI é uma camada de apresentação: armazenamento, criptografia, descriptografia, clipboard e OTP continuam sendo responsabilidade do `npass`.

## Requisitos

- Bash 4.3+
- `tput` e `stty` (normalmente fornecidos por ncurses/coreutils/util-linux, conforme a distribuição)
- `npass-store` **2.8** instalado e configurado conforme a documentação do projeto (versão-alvo; a TUI aborta se a versão for incompatível — `NPASS_TUI_SKIP_VERSION_CHECK=1` ignora a checagem)
- Terminal interativo com suporte a terminfo

Não depende de Python, `dialog`, `fzf` ou `gum`.

## Estrutura

O código-fonte fica em `lib/*.bash`. `build.sh` concatena os arquivos, em ordem, no
executável único `bin/npass-tui` (no `.gitignore`), do mesmo modo que o npass-store gera `bin/npass`.
O binário gerado não procura `lib/` em tempo de execução: pode ser copiado para qualquer lugar.

```
lib/00-core.bash    # estado, traps, modo do terminal, sanitização
lib/01-input.bash   # teclado → tokens lógicos
lib/02-backend.bash # contrato com a CLI npass (versão, identidades, caminhos)
lib/03-render.bash  # telas e renderização
lib/04-actions.bash # ações do usuário (clip, otp, insert, edit, rm, filtro)
lib/99-main.bash    # checagens de ambiente, loop principal e ponto de entrada (sempre por último)
build.sh            # lib/*.bash -> bin/npass-tui
install.sh          # reconstrói e instala bin/npass-tui
```

## Instalar

```sh
sudo ./install.sh                    # /usr/bin/npass-tui
./install.sh --prefix="$HOME/.local" # só para o seu usuário
./install.sh --uninstall
```

## Executar sem instalar

```sh
./build.sh
./bin/npass-tui
```

Se `npass` não estiver no `PATH`, informe o caminho:

```sh
NPASS_BIN="$HOME/.local/bin/npass" ./bin/npass-tui
```

## Controles

- `↑` / `↓` ou `j` / `k`: navegar
- `Enter`: abrir identidade ou visualizar entrada
- `/`: filtrar caminhos; filtro vazio mostra tudo
- `c`: copiar senha via `npass clip`
- `o`: consultar OTP via `npass otp`
- `a`: criar entrada, informando o caminho; o próprio `npass insert` solicita a senha duas vezes sem eco e confirma antes de sobrescrever
- `e`: editar a entrada selecionada com `npass edit` e o editor definido em `$EDITOR`
- `d`: excluir a entrada selecionada; exige digitar `sim`, avisa sobre anexos de backup e mantém a confirmação nativa do `npass rm`
- `Esc`: voltar
- `q`: voltar ou sair

## Segurança e escopo

- Identidades são obtidas por `npass identities`; caminhos por `npass ls --flat ID`.
- O conteúdo é obtido apenas quando solicitado, via `npass show --raw ID CAMINHO`.
- A TUI não grava segredos em arquivos temporários nem implementa o formato de armazenamento do npass.
- A TUI delega criação, edição e exclusão à CLI do `npass`; não implementa armazenamento nem parsing de escrita próprio. Movimentação e geração ainda não fazem parte da interface.
- O conteúdo exibido fica na memória do processo e pode ser capturado por gravação de terminal ou visto por alguém com acesso à tela. Use em uma sessão confiável.

## Estado

Versão inicial: navegação por identidades e caminhos, preview com scroll, filtro simples, clipboard e OTP. A implementação ainda precisa ser validada manualmente contra um cofre real em diferentes terminais.
