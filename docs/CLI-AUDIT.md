# Auditoria da CLI do npass para o npass-tui

Data da auditoria: 2026-10-24

## Escopo e fontes

Auditoria feita a partir do README e dos arquivos de despacho/uso do `npass` presentes na biblioteca de arquivos do projeto, além do código atual de `npass-tui`. A consulta direta ao repositório `HGBits/npass` falhou com HTTP 404 pela integração disponível; portanto, os detalhes abaixo refletem os arquivos de fonte disponíveis e devem ser conferidos contra a versão instalada antes de habilitar escrita.

## Comandos identificados

| Operação | Comando/forma documentada | Uso na TUI |
|---|---|---|
| Listar identidades | `npass identities` (alias `ids`) | Já usado |
| Criar identidade | `npass init ID RECIPIENT...` | Futuro; fluxo sensível, pode pedir chave GPG |
| Ler segredo | `npass show ID CAMINHO` | Já existe, mas a TUI usa `show --raw`; confirmar se `--raw` existe na versão-alvo |
| Inserir/atualizar entrada | `npass insert [-f] ID CAMINHO` (alias `add`) | Fase seguinte |
| Editar entrada | `npass edit ID CAMINHO` | Fase seguinte; usa `$EDITOR`, então não é um editor embutido |
| Excluir entrada | `npass rm [-f] ID CAMINHO` (aliases `remove`, `delete`) | Fase seguinte; confirmação explícita na TUI |
| Renomear/mover entrada | `npass mv ID CAMINHO DEST` (alias `rename`) | Futuro |
| Listar caminhos | `npass ls ID [DIR]` (alias `list`) | A TUI usa atualmente `npass tree --flat ID`; provável incompatibilidade a corrigir |
| Gerar senha | `npass generate [-n|-c|-f] [--in-place] ID CAMINHO [LEN]` (alias `gen`) | Futuro |
| Rotacionar em lote | `npass update [OPÇÕES] ID PADRÃO...` | Futuro; requer UX cuidadosa e confirmação |
| Buscar caminhos | `npass find ID PADRÃO` | Pode alimentar filtro/busca |
| Buscar conteúdo | `npass grep ID [OPÇÕES] PADRÃO` | Futuro; não renderizar segredos encontrados em logs/status |
| Copiar senha/campo/entrada | `npass clip [CAMPO] ID CAMINHO` | Já usa forma básica |
| OTP | `npass otp ID CAMINHO` | Já usa geração de código |
| Copiar OTP | `npass otp clip ID CAMINHO` | Alternativa preferível para não exibir código na tela |
| Inserir/atualizar OTP | `npass otp insert [-f] ID CAMINHO` | Futuro |
| URI/QR de OTP | `npass otp uri [-c|-q] ID CAMINHO` | Futuro; URI contém segredo e exige cuidado |
| Validar URI OTP | `npass otp validate URI` | Futuro |
| Assinar identidade | `npass sign ID [KEYID]` | Administração avançada |
| Extensões | `npass extension list|sign|install ...` | Fora do escopo inicial |
| Git do cofre | `npass git ARGS...` | Fora do escopo inicial; evitar expor saída sensível |
| Tomb | `npass tomb create|open|close|status|list ID` | Administração avançada; confirmar suporte na versão-alvo |
| Importação | `migrate` / `migrate-secrets` aparecem em uma versão do uso; outra fonte indica que foram movidos para a extensão `npass-import` | Não integrar até confirmar a versão |

## Incompatibilidades e riscos encontrados

1. **Listagem de caminhos:** a TUI chama `npass tree --flat ID`, mas a CLI disponível documenta `npass ls ID [DIR]`. O parser deve ser adaptado ao formato real de `ls` (a saída pode incluir o nome da identidade e indentação).
2. **Leitura bruta:** a TUI chama `npass show --raw ID CAMINHO`, enquanto a referência disponível documenta `npass show ID CAMINHO`. Confirmar suporte a `--raw` antes de confiar nessa chamada.
3. **Inserção não é só criação:** `insert` pode atualizar uma entrada existente; a TUI precisa detectar conflito ou exigir confirmação/usar `-f` somente após confirmação explícita.
4. **Edição delegada ao editor:** `npass edit` abre `$EDITOR`; a TUI deve suspender seu modo raw, restaurar echo/icanon e redesenhar a tela após o editor fechar.
5. **Exclusão e movimento:** operações destrutivas precisam confirmação que mostre identidade e caminho completos; cancelar com Esc não pode executar nada.
6. **Segredos em tela/argumentos:** evitar segredos em mensagens de status, logs e argumentos de processos quando o CLI oferecer entrada por stdin. Preferir `npass otp clip` se a intenção for copiar OTP.
7. **Fonte/versionamento:** arquivos disponíveis incluem referências de versões diferentes para importação. Consultar `npass --help` e comandos `--help` na versão instalada antes de implementar cada ação.

## Recomendação para a próxima fase

Antes de adicionar operações de escrita, corrigir e testar os dois pontos de compatibilidade de leitura/listagem. Depois implementar, nesta ordem:

1. `insert` com detecção de entrada existente e confirmação;
2. `edit` com restauração segura do terminal ao invocar `$EDITOR`;
3. `rm` com confirmação explícita;
4. `mv` e `generate`;
5. operações OTP adicionais e busca.

## Verificações necessárias no ambiente-alvo

Executar sem passar dados secretos:

```sh
npass --help
npass ls --help
npass show --help
npass insert --help
npass edit --help
npass rm --help
npass mv --help
npass generate --help
npass update --help
npass otp --help
```

A CLI pode não implementar `--help` individual para todos os comandos; nesse caso, usar apenas a mensagem de uso retornada e conferir a versão instalada. Não executar operações destrutivas como teste contra um cofre real.
