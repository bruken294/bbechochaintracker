# BB Echo Chain Tracker

Countdown bars for Blood Death Knights using **Boiling Point**: one bar for the 15-second proc window and one for the 3-second automatic Blood Boil echo.

## Features

- Bars drain as they count down, with the time left and the buff name on each bar.
- Resize by dragging the corner grip while unlocked, or with the width and height sliders.
- A real Edit Mode frame: click it to select, drag to move, and change size, texture, icon and more in its Edit Mode dialog (or use `/bbe unlock`).
- `/bbe icon` shows or hides the spell icon.
- Pick colors (with opacity) for every bar state, the background, the border and the text.
- Bar textures: Blizzard's own plus every LibSharedMedia texture, including Details' and media packs'.
- Rotation chain can show the empowered Blood Boil step, or only the echo chain.
- Rename either bar.
- Horizontal or vertical bars.
- Show or hide the spell icon, buff name, countdown time and spark.
- Display modes: 15s only, 3s only, both, or rotation chain.
- `/bbe` opens settings.

## Rotation chain

One bar follows the whole Boiling Point rotation:

1. **Boiling Point ready** (proc color): an empowered Blood Boil is waiting, draining over 15s.
2. Cast it and the bar becomes **Echo x1**, draining over 3s.
3. Cast Dancing Rune Weapon: a thin strip under the bar counts down its window.
4. Spam Heart Strike. When a new Boiling Point procs during an echo, the bar turns green (**linked**): the echo will use the proc itself and start the next echo, and the count goes up.
5. While the bar is red (**need proc**), the chain ends when the echo runs out unless you get a proc first. The bar then shows **Chain ended xN** for 2 seconds by default. Set this from 0 (the bar hides at once) to 10 seconds, or show it as separate text you can move on its own in Edit Mode.

## Commands

- `/bbe chain`: switch to the rotation chain bar
- `/bbe testchain`: play a sample chain
- `/bbe`: open settings
- `/bbe test3`, `/bbe test15`: test a bar
- `/bbe unlock`, `/bbe lock`: move and resize the bars, or lock them
- `/bbe hide`: hide active bars

## Credits

Bundled libraries, unmodified, each under its own license: LibEditMode by p3lim (see `Libs/LibEditMode/LICENSE.txt`), LibSharedMedia-3.0, CallbackHandler-1.0 and LibStub.

The proc and echo detection comes from [Boiling Point Echo](../BoilingPointEcho) by Wan, used under the MIT License:

> Copyright (c) 2026 Wan
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
