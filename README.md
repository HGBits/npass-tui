# npass-tui

Interface de terminal em **Bash** para o [`npass`](https://github.com/HGBits/npass). O npass é uma dependência obrigatória e continua sendo a única camada responsável por armazenamento, descriptografia e operações com segredos. A TUI apenas apresenta as identidades e os caminhos e encaminha comandos.

## Requisitos

- Bash 4+
- [`dialog`](https://invisible-island.net/dialog/) para os menus de terminal
- `npass` instalado e configurado conforme a documentação do projeto
- `sed`

## Executar

```sh
chmod +x npass-tui
./npass-tui
```

Se `npass` não estiver no `PATH`, informe o caminho do executável:

```sh
NPASS_BIN="$HOME/.local/bin/npass" ./npass-tui
```

Também é possível selecionar outro executável de `dialog` com `DIALOG_BIN`.

## Controles

A navegação é feita pelos menus do `dialog`. Selecione uma identidade e depois um caminho para abrir o menu de ações:

- **Abrir**: visualiza o conteúdo retornado por `npass show --raw`
- **Copiar**: delega a cópia a `npass clip`
- **OTP**: delega a consulta a `npass otp`
- **Filtrar**: filtra caminhos por um trecho de texto

## Decisões de segurança

- A lista de identidades vem de `npass identities`; os caminhos vêm de `npass tree --flat`.
- A TUI não implementa armazenamento, criptografia, descriptografia nem o formato md1.
- Senhas não são gravadas em arquivos temporários. O conteúdo de uma entrada é mantido em memória pelo shell e exibido pelo `dialog`.
- A primeira versão é somente leitura, além de copiar senha e consultar OTP. Criar, editar e excluir entradas ficam a cargo de futuras operações suportadas pelo próprio `npass`.
- Use em um terminal confiável. A visualização de segredos pode ficar exposta a pessoas próximas ou ao histórico de gravação do terminal.
