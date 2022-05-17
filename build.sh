#!/bin/sh

nasm -f bin -O0 -o spong main.asm
chmod +x spong
