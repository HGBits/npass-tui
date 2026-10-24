# npass-tui

Interface de terminal para o [`npass`](https://github.com/HGBits/npass). O npass é uma dependência obrigatória e continua sendo a única camada responsável por armazenamento, descriptografia, formato md1, clipboard e OTP. Esta TUI só apresenta caminhos e encaminha comandos.

## Requisitos

- Python 3.10+ (biblioteca padrão `curses`; em Windows, seria necessário `windows-curses`)
- `npass` instalado e configurado conforme a documentação do projeto
- Terminal compatível com curses

## Executar

```sh
chmod +x npass-tui
./npass-tui
```

Se `npass` não estiver no `PATH`, informe o caminho do executável:

```sh
NPASS_BIN="$HOME/.local/bin/npass" ./npass-tui
```

## Controles

- `↑` / `↓` ou `j` / `k`: navegar
- `Enter`: selecionar identidade ou abrir entrada
- `/`: filtrar caminhos
- `c`: copiar senha usando `npass clip`
- `o`: obter OTP usando `npass otp`
- `Esc`: voltar
- `q`: voltar ou sair

## Decisões de segurança

- A lista vem de `npass identities` e `npass tree --flat`; a listagem não pede descriptografia.
- A visualização chama `npass show --raw`; a TUI não interpreta nem reimplementa md1.
- Clipboard e OTP são delegados diretamente a `npass`.
- Nenhuma senha é persistida pela TUI. A visualização é exibida em memória no terminal; use em sessão confiável e evite gravações de terminal.
- A primeira versão é somente leitura, além de copiar senha e consultar OTP. Criar, editar e apagar entradas continuam fora do escopo da interface.
