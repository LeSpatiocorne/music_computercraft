# ComputerCraft Music Party

This is a music player for ComputerCraft that allows you to listen to music with
your friends and team members.
The program relies on webserver running in background to handle convertions requests and serve the audio directly to the computer.

# This is mostly a proof of concept

I've been having fun with computercraft so far and I'm playing with the capabilities that gives me API of the mod. My goal was to make this program as
a libfree program that don't rely on physical installations on the game server.

# Here how it works

We got 3 layers:
1. The program ComputerCraft that you can manipulate
2. The webserver that handle requests from the program, manage rooms and download musics from youtube.
3. A local clone of [music.made.cc](https://github.com/SquidDev-CC/music.madefor.cc) that handles the conversion into the right format.

# How to install

open computer and past this command :
```pastebin run https://pastebin.com/bBuGnETS```