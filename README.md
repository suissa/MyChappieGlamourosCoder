# ⚡ MyChappie Glamouros Coder (Zig v0.16)

<p align="center">
  <b>Assistente de Código Autônomo e Glamouroso para Terminal</b><br />
  Desenvolvido nativamente em <b>Zig v0.16</b> para a arquitetura <b>Multi-Plane AllasCode</b> (Planes/Agents).
</p>

---

## 🌟 Destaques

- **Puro Zig v0.16**: Compilação nativa com zero dependências externas pesadas (`CGO_ENABLED=0`, binário estático e ultrarrápido).
- **Interface TUI Glamour**: Estilização TrueColor ANSI 24-bit com caixas arredondadas, badges de status, banners neon e renderização de diffs coloridos.
- **Ciclo Autônomo SOTA-DD**: Intake da meta do desenvolvedor, raciocínio passo a passo, chamada e despacho recursivo de ferramentas e auto-recuperação de erros.
- **Ferramentas Nativas de Código**:
  - `view`: Leitura com paginação e numeração de linhas.
  - `write`: Criação e sobrescrita segura com criação recursiva de diretórios.
  - `edit`: Modificação cirúrgica por substituição exata com validação de unicidade.
  - `bash`: Execução segura de comandos do sistema com captura de stdout e stderr.
  - `grep`: Busca textual recursiva de alta velocidade em árvores de diretórios.
  - `glob`: Descoberta e enumeração de arquivos por máscaras de padrão.
  - `todos`: Planejamento e acompanhamento de tarefas para objetivos complexos.
  - `question`: Interação interativa para tomada de decisões com o usuário.
- **Multi-Provedor LLM**: Suporte nativo a Google Gemini, OpenAI/OpenRouter/DeepSeek, Anthropic Claude, Ollama local e Mock determinístico offline.

---

## 🚀 Como Compilar e Executar

### Pré-requisito
- **Zig v0.16.0** instalado e acessível no seu `PATH`.

### 1. Compilação
```bash
# Na raiz de Planes/Agents/MyChappieGlamourosCoder
zig build
```
O binário será gerado em:
`zig-out/bin/mychappie-coder.exe` (Windows) ou `zig-out/bin/mychappie-coder` (Linux/macOS).

### 2. Executar a Suíte de Testes
```bash
zig build test
```
Executa todos os 20 testes unitários automatizados (TUI, Tools, Agent Loop, Session, Mock Provider e Permissões).

### 3. Comandos do CLI

```bash
# Ver informações de versão e runtime
zig-out/bin/mychappie-coder version

# Listar catálogo de ferramentas
zig-out/bin/mychappie-coder tools

# Listar provedores de LLM suportados
zig-out/bin/mychappie-coder models

# Diagnóstico do workspace e contexto
zig-out/bin/mychappie-coder info

# Executar um objetivo com o agente autônomo
zig-out/bin/mychappie-coder run "Crie um arquivo teste.txt com conteúdo de demonstração"
```

---

## 🏛️ Estrutura do Projeto

```
build.zig.zon                          Manifesto de pacote Zig 0.16
build.zig                              Script de build (módulo da biblioteca + binário CLI + testes)
src/
  main.zig                             CLI entrypoint e despachante de comandos
  root.zig                             Módulo público da biblioteca 'mychappie_coder'
  glamour.zig                          Motor de estilização visual TUI e ANSI Truecolor
  config.zig                           Descoberta de contexto e variáveis de ambiente
  agent/
    agent.zig                          Motor autônomo CoderAgent
    coordinator.zig                    Especialização de papéis (Coder, Architect, Reviewer)
    prompts.zig                        System prompts nativos
    session.zig                        Histórico e estado da sessão
  tools/
    tool.zig                           Interface universal de ferramentas
    view.zig, write.zig, edit.zig      Ferramentas de manipulação de código
    bash.zig                           Ferramenta de terminal e processos
    grep.zig, glob.zig                 Ferramentas de busca e navegação
    todos.zig, question.zig            Ferramentas de planejamento e diálogo
    registry.zig                       Registro e despacho central
  llm/
    provider.zig                       Contratos abstratos de LLM
    mock.zig                           Provedor mock determinístico para testes
    gemini.zig, openai.zig             Clientes HTTP REST para nuvem
    anthropic.zig, ollama.zig          Clientes HTTP REST para Claude e Ollama local
  permission/
    permission.zig                     Motor de segurança e aprovação
legacy_go/                             Arquivo histórico do código Go original
```

---

## 📄 Licença
Distribuído sob os termos da licença MIT. Parte do ecossistema AllasCode.
