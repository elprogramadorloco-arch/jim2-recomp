# Earthworm Jim 2 Recompiled

[English](#english) · [Español](#español) · [Português](#português)

---

## English

### What is this project?

A native Windows version of the PlayStation release of *Earthworm Jim 2*,
produced by **static recompilation** with
[psxrecomp](https://github.com/mstan/psxrecomp): the game's MIPS code is
translated to C and compiled into a normal Windows executable. It is not an
emulator and it does not include the game. You build a private copy on your
own PC from a disc you own.

The boot loader and all 19 game executables (main menu, the 17 levels and the
ending) are recompiled ahead of time. Every level was checked against the
DuckStation emulator during development.

### Requirements

- 64-bit Windows 10 or 11.
- About 6 GB of free disk space and 16 GB of RAM recommended for the build.
- An Internet connection for the first build. `run.bat` downloads, verifies
  (SHA-256) and uses a portable toolchain (clang, CMake, Ninja, Python). You do
  **not** need Visual Studio, Build Tools, CMake or Python installed.
- Your dump of *Earthworm Jim 2* (Europe), PlayStation, serial `SLES-00343`:
  the Redump set with one `.cue` and 15 `.bin` tracks. Track 01 SHA-256:
  `D251CF65BB60EE375778F4369CF74FB88371E07EAB51EC337C0AD34F8DEF932B`.

### How to use it

1. Put the `.cue` and its 15 `.bin` files in `data`.
2. Run `run.bat`.
3. It validates the disc, prepares the toolchain, downloads the framework
   sources at pinned commits, recompiles the game and builds the runtime. The
   first build takes a while (roughly 30-60 minutes depending on the PC).
4. Play with `out\EarthwormJim2_Recompiled.exe`. On first launch, pick the same
   `.cue` if it asks for the disc.

Later runs of `run.bat` only redo the steps whose inputs changed.
`run.bat -ValidateOnly` only checks the disc and free space.

Do not share `data`, `out` or `tools\.build`: they contain your disc or code
generated from it.

### Updates

Run `update.bat`. It reads the latest GitHub Release, shows what's new,
downloads the source-only package, verifies its SHA-256, replaces the public
source files (never `data`, `out` or `tools\.build`) and rebuilds what changed.
If something fails, the previous version is restored.

### Status

| Item | Status |
| --- | --- |
| Boot, menus, debug menu | OK |
| All 17 levels load and play (checked against DuckStation) | OK |
| Level-to-level transitions, FMV between levels, ending | Recompiled; not yet verified end to end |
| Audio | SPU support in psxrecomp is still partial (some effects such as reverb) |

---

## Español

### ¿Qué es este proyecto?

Una versión nativa para Windows de *Earthworm Jim 2* de PlayStation, creada por
**recompilación estática** con [psxrecomp](https://github.com/mstan/psxrecomp):
el código MIPS del juego se traduce a C y se compila como un ejecutable normal
de Windows. No es un emulador y no incluye el juego. Tú generas una copia
privada en tu PC a partir de un disco que te pertenece.

El cargador y los 19 ejecutables del juego (menú principal, los 17 niveles y el
final) se recompilan por adelantado. Durante el desarrollo se comprobó cada
nivel frente al emulador DuckStation.

### Requisitos

- Windows 10 u 11 de 64 bits.
- Unos 6 GB libres y se recomiendan 16 GB de RAM para la compilación.
- Conexión a Internet en la primera compilación. `run.bat` descarga, verifica
  (SHA-256) y usa una toolchain portable (clang, CMake, Ninja, Python). **No**
  necesitas Visual Studio, Build Tools, CMake ni Python instalados.
- Tu volcado de *Earthworm Jim 2* (Europa), PlayStation, serie `SLES-00343`:
  el set de Redump con un `.cue` y 15 pistas `.bin`. SHA-256 de la pista 01:
  `D251CF65BB60EE375778F4369CF74FB88371E07EAB51EC337C0AD34F8DEF932B`.

### Cómo se usa

1. Pon el `.cue` y sus 15 `.bin` en `data`.
2. Ejecuta `run.bat`.
3. Valida el disco, prepara la toolchain, descarga el framework en commits
   fijados, recompila el juego y compila el runtime. La primera vez tarda
   (aproximadamente 30-60 minutos según el PC).
4. Juega con `out\EarthwormJim2_Recompiled.exe`. Si al abrirlo pide el disco,
   elige el mismo `.cue`.

Las siguientes ejecuciones de `run.bat` solo repiten los pasos cuyas entradas
cambiaron. `run.bat -ValidateOnly` solo comprueba el disco y el espacio libre.

No compartas `data`, `out` ni `tools\.build`: contienen tu disco o código
generado a partir de él.

### Actualizaciones

Ejecuta `update.bat`. Lee la última Release de GitHub, muestra las novedades,
descarga el paquete (solo código fuente), verifica su SHA-256, reemplaza los
archivos públicos (nunca `data`, `out` ni `tools\.build`) y recompila lo que
cambió. Si algo falla, restaura la versión anterior.

### Estado

| Elemento | Estado |
| --- | --- |
| Arranque, menús, menú de depuración | OK |
| Los 17 niveles cargan y se juegan (comparados con DuckStation) | OK |
| Transiciones entre niveles, vídeos entre niveles, final | Recompilados; sin verificar de principio a fin |
| Audio | El soporte SPU de psxrecomp aún es parcial (algunos efectos como reverb) |

---

## Português

### O que é este projeto?

Uma versão nativa para Windows de *Earthworm Jim 2* de PlayStation, criada por
**recompilação estática** com [psxrecomp](https://github.com/mstan/psxrecomp):
o código MIPS do jogo é traduzido para C e compilado como um executável
normal do Windows. Não é um emulador e não inclui o jogo. Você gera uma cópia
privada no seu PC a partir de um disco que lhe pertence.

O carregador e os 19 executáveis do jogo (menu principal, as 17 fases e o
final) são recompilados antecipadamente. Cada fase foi comparada com o
emulador DuckStation durante o desenvolvimento.

### Requisitos

- Windows 10 ou 11 de 64 bits.
- Cerca de 6 GB livres e 16 GB de RAM recomendados para a compilação.
- Conexão com a Internet na primeira compilação. O `run.bat` baixa, verifica
  (SHA-256) e usa uma toolchain portátil (clang, CMake, Ninja, Python). **Não**
  é preciso ter Visual Studio, Build Tools, CMake ou Python instalados.
- Seu dump de *Earthworm Jim 2* (Europa), PlayStation, série `SLES-00343`:
  o set Redump com um `.cue` e 15 faixas `.bin`. SHA-256 da faixa 01:
  `D251CF65BB60EE375778F4369CF74FB88371E07EAB51EC337C0AD34F8DEF932B`.

### Como usar

1. Coloque o `.cue` e os 15 `.bin` em `data`.
2. Execute `run.bat`.
3. Ele valida o disco, prepara a toolchain, baixa o framework em commits fixos,
   recompila o jogo e compila o runtime. A primeira vez demora (cerca de 30-60
   minutos, dependendo do PC).
4. Jogue com `out\EarthwormJim2_Recompiled.exe`. Se pedir o disco ao abrir,
   escolha o mesmo `.cue`.

As próximas execuções do `run.bat` só refazem as etapas cujas entradas mudaram.
`run.bat -ValidateOnly` só verifica o disco e o espaço livre.

Não compartilhe `data`, `out` nem `tools\.build`: contêm seu disco ou código
gerado a partir dele.

### Atualizações

Execute `update.bat`. Ele lê a última Release do GitHub, mostra as novidades,
baixa o pacote (somente código-fonte), verifica o SHA-256, substitui os
arquivos públicos (nunca `data`, `out` ou `tools\.build`) e recompila o que
mudou. Se algo falhar, a versão anterior é restaurada.

### Estado

| Item | Estado |
| --- | --- |
| Inicialização, menus, menu de depuração | OK |
| As 17 fases carregam e são jogáveis (comparadas com o DuckStation) | OK |
| Transições entre fases, vídeos entre fases, final | Recompilados; ainda não verificados de ponta a ponta |
| Áudio | O suporte SPU do psxrecomp ainda é parcial (alguns efeitos como reverb) |

---

## Legal

See [LEGAL.md](LEGAL.md). Not affiliated with Shiny Entertainment, Interplay,
Virgin Interactive, Playmates, Sony or any other rightsholder. This repository
and its Releases contain no game data and no code generated from the game.
