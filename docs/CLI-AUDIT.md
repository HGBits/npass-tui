# Auditoria da CLI do npass para o npass-tui

Data da revisão: 2026-10-24

## Fonte autoritativa consultada

Repositório: https://github.com/HGBits/npass-store  
README: https://github.com/HGBits/npass-store/blob/master/README.md  
Código consultado na revisão: `lib/15-tree.bash` e `lib/03-store.bash`.

O README identifica o npass como versão 2.5. Esta revisão substitui as suposições de compatibilidade baseadas em cópias antigas de documentação.

## Operações confirmadas

| Operação | Forma documentada/confirmada | Observações para a TUI |
|---|---|---|
| Listar identidades | `npass identities` (alias `ids`) | A saída inclui contagem: `ID - N senhas`. |
| Criar identidade | `npass init ID RECIPIENT...` | Fluxo administrativo; pode envolver GPG. |
| Listar caminhos | `npass tree --flat ID [DIR]` | Confirmado em `lib/15-tree.bash`; um caminho lógico por linha. `ls/list` foi removido. |
| Ler entrada sem renderização | `npass show --raw ID CAMINHO` | Confirmado no README; adequado para preview, com cuidado ao renderizar sequências de controle. |
| Inserir entrada | `npass insert [-f] ID CAMINHO` | Entrada existente pede confirmação; `-f` força substituição. |
| Editar entrada | `npass edit ID CAMINHO` | Abre `$EDITOR`, usa arquivo temporário seguro, valida formato md1 antes de gravar; também cria entrada se ela ainda não existir. |
| Excluir entrada | `npass rm [-f] ID CAMINHO` | Pede confirmação por padrão; anexos de backup podem ser removidos junto. |
| Renomear/mover | `npass mv ID ORIGEM DESTINO` | Mesma identidade: altera o mapa; entre identidades: decifra e recifra para o destino. |
| Gerar senha | `npass generate [-n] [-c] [-f] [--in-place] ID CAMINHO [TAMANHO]` | Senha vai para stdout por padrão; `-c` copia. Pode sobrescrever com confirmação. |
| Buscar caminhos | `npass find ID PADRÃO` | Pesquisa nomes de caminhos, não conteúdo. |
| Buscar conteúdo | `npass grep ID [OPÇÕES] PADRÃO` | Decifra entradas; saída pode conter segredos. Não despejar resultados automaticamente na interface. |
| Copiar senha/campo | `npass clip [CAMPO] ID CAMINHO` | A senha é o padrão; `all` copia o documento inteiro. |
| Gerar OTP | `npass otp ID CAMINHO` | Mostra o código; TOTP/HOTP são suportados. |
| Copiar OTP | `npass otp clip ID CAMINHO` | Preferível para ação de cópia sem mostrar o código na tela. |
| Inserir OTP | `npass otp insert [-f] ID CAMINHO` | Operação de escrita separada. |
| URI OTP | `npass otp uri ID CAMINHO` | URI contém segredo; não mostrar ou registrar sem ação explícita. |
| Rotacionar em lote | `npass update ...` | Adiar até haver confirmação de escopo e resumo de alterações. |
| Extensões, Git, importação, tomb e passkeys | Ver README e ajuda por categoria | Escopo avançado; confirmar cada subcomando antes de integrar. |

## Correções em relação à auditoria anterior

1. **Não há incompatibilidade na listagem atual:** `npass tree --flat ID` é a interface de máquina documentada e implementada. `npass ls/list` foi removido.
2. **Não há incompatibilidade na leitura bruta:** `npass show --raw ID CAMINHO` é documentado pela versão consultada.
3. O projeto do npass é modular: o executável é gerado a partir de `lib/` com `./build.sh`. A integração da TUI não deve editar nem depender de detalhes internos desses módulos.

## Riscos e requisitos de UX

- **Terminal:** antes de executar `npass edit`, restaurar o estado original do terminal; depois, reativar o modo de leitura da TUI e redesenhar a tela. O editor externo precisa de entrada/saída normais.
- **Sobrescrita:** `insert` atualiza uma entrada existente. Não passar `-f` sem confirmação explícita.
- **Exclusão:** confirmar mostrando identidade e caminho completos. Esc cancela sem executar.
- **Movimentação:** distinguir renomeação na mesma identidade de movimentação entre identidades; validar o destino antes de chamar o comando.
- **Segredos no terminal:** remover sequências de controle ANSI/OSC de nomes e conteúdo antes de desenhá-los. Evitar guardar saídas que contenham segredos em status, logs ou arquivos temporários da TUI.
- **OTP:** oferecer ações separadas para mostrar e copiar; para copiar, usar `npass otp clip ID CAMINHO`.
- **Geração:** deixar claro quando a operação cria uma entrada, substitui a senha inteira ou troca somente a senha com `--in-place`.
- **Testes:** usar um executável `npass` simulado e fixtures temporárias; não executar testes destrutivos contra o cofre real.

## Ordem recomendada para a implementação

1. Reforçar sanitização de texto e testes de parsing da saída.
2. Adicionar criação de entrada com confirmação de sobrescrita.
3. Adicionar edição delegada ao `$EDITOR`, restaurando o terminal corretamente.
4. Adicionar exclusão com confirmação.
5. Adicionar geração de senha e movimentação/renomeação.
6. Adicionar operações OTP complementares e busca por caminhos.
7. Considerar operações em lote e administração somente depois de testes específicos.

## Validação no ambiente instalado

A documentação do repositório é a referência da versão consultada, mas a versão instalada ainda deve ser verificada sem revelar dados secretos:

```sh
npass help
npass help entradas
npass help gerar
npass help otp
npass tree --help
npass show --help
```

A CLI usa ajuda por categoria; nem todo comando necessariamente implementa uma opção `--help` própria. Não executar operações destrutivas apenas para descobrir sua sintaxe.
