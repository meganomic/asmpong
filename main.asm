BITS 64
default rel
    org 0x40000 ; default virtual address

; ELF64 Header
ehdr:
                db 0x7F, "ELF", 2, 1, 1, 0 ; e_ident[16]
                dq 0 ;
                dw 2 ; e_type
                dw 62 ; e_machine
                dd 1 ; e_version
                dq _start; e_entry           /* Entry point virtual address */
                dq interphdr - $$; e_phoff   /* Program header table file offset */
                dq 0 ; e_shoff               /* Section header table file offset */
                dd 0 ; e_flags
                dw 64 ; e_ehsize
                dw 56 ; e_phentsize
                ;dw 3 ; e_phnum
                ;dw 0 ; e_shentsize
                ;dw 0 ; e_shnum
                ;dw 0 ; e_shstrndx


interphdr:
                dd 3 ; p_type
                dd 4 ; p_flags
                dq interp-$$ ; p_offset                /* Segment file offset */
                dq interp ; p_vaddr                    /* Segment virtual address */
                dq 0 ; p_paddr                         /* Segment physical address */
                dq intend-interp ; p_filesz            /* Segment size in file */
                dq intend-interp ; p_memsz             /* Segment size in memory */
                dq 1 ; p_align                         /* Segment alignment, file & memory */


dynamichdr:
                dd 2 ; p_type
                dd 4 ; p_flags
                dq dynamic-$$ ; p_offset              /* Segment file offset */
                dq dynamic ; p_vaddr                  /* Segment virtual address */
                dq 0 ; p_paddr;                       /* Segment physical address */
                dq 6*8 ; p_filesz                     /* Segment size in file */
                dq 6*8 ; p_memsz                      /* Segment size in memory */
                dq 1 ; p_align                        /* Segment alignment, file & memory */


phdr:
                dd 1 ; p_type
                dd 7 ; p_flags
                dq 0 ; p_offset                       /* Segment file offset */
                dq $$ ; p_vaddr                       /* Segment virtual address */
                dq 0 ; p_paddr                        /* Segment physical address */
                dq end_of_file-$$ ; p_filesz          /* Segment size in file */
                dq end_of_bss-$$ ; p_memsz            /* Segment size in memory */
                dq 4096 ; p_align                     /* Segment alignment, file & memory */


dynamic:
                dq 1 ; DT_NEEDED
                dq libsdl-strtab
                dq 0x15 ; DT_DEBUG
debug:          dq 0 ; This will contain a pointer to r_debug

                dq 5 ; DT_STRTAB
                dq strtab
                dq 6 ; DT_SYMTAB
                dq strtab
                dq 0 ; DT_NULL


interp:
db `/lib64/ld-linux-x86-64.so.2` ; Uses null byte from strtab
strtab:
db 0
libsdl:
db `libSDL2.so\0`
intend:


_start:
    ; Using debug is mostly portable I think
    mov rbx, [debug] ; r_debug pointer

    ; Ignore the first two, it's our program and the vdso
    mov rbx, [rbx+8] ; link_map pointer - Our binary
    mov rbx, [rbx+24] ; next pointer - vDSO

    ; RSI+8 contains the address for the vDSO link map. THIS IS NOT PORTABLE
    ;lea rbx, [rsi+8]

.nextlib:
    mov rbx, [rbx+24] ; Pointer to next link map

    ; If the next linkmap pointer is zero, we are done
    test rbx, rbx
    jz short real_entry

    ; Not sure when/if this is actually needed
    ;mov rsi, [rbx+8] ; library name
    ;cmp byte [rsi], 0
    ;jz short .nextlib


    mov rcx, [rbx+16] ; l_ld = dynamic section

.nt:
    ; Find the String table
    add rcx, byte 16 ; Assume that the dynamic table never starts off with DT_STRTAB. This is true for all libraries I looked at.
    cmp [rcx], byte 5 ; DT_STRTAB
    jne short .nt

    mov rdx, [rcx + 8] ; String base - We add this to st_name to get the pointer to the string
    mov rcx, [rcx + 24] ; Symbols. Assume that this immediately follows DT_STRTAB

.sf:
    ; If st_size is zero we don't want it, st_size is a qword but it's highly doubtful that the entire lowest byte is 0
    cmp [rcx+16], byte 0 ; st_size
    jz short .nextentry

    mov esi, [rcx]  ; Read symbol name offset (st_name)
    add rsi, rdx ; Add string table offset.


;--------------------------------------------;
; Check hash of symbol against our hashtable ;
;--------------------------------------------;
.checkhashes:
    ; Check all hashes against symbol
    push rdx

    xor ebp, ebp

.crc32:
    lodsb ; Load next byte in string to AL
    crc32 ebp, al
    cmp al, 0 ; Check for end of string
    jnz short .crc32


    mov edi, hashpointers
    mov edx, hashtable

.nexthash:
    ; If the hash has already been resolved go to next one
    ;cmp qword [rsi], byte 0
    ;jnz short .skiphash

    cmp ebp, dword [rdx] ; Compare against the hash in the hash table
    jz short .foundhash

;.skiphash:
    ; Check if next hash value is zero
    add edi, byte 8
    add edx, byte 4
    cmp dword [rdx], byte 0 ; If it's zero we've checked them all
    jnz short .nexthash ; Check the next hash

    jmp short .allhashesdone ; Otherwise we're done with this symbol

.foundhash:
    mov eax, [rcx+8] ; function addr offset
    add rax, [rbx] ; Add l_addr to function addr offset

    cmp [rcx+4], byte 26 ; Check if it's a GLOBAL+IFUNC symbol
    jnz short .notifunc


    push rcx
    ;push rbx
    ;push rsi

    ; This potentially trashes a bunch of registers. The new address is returned in RAX
    ; The only registers you have to save are RCX, RBX, and RSI. RDX is already saved.
    call rax ; Call the IFUNC function to set it up

    ;pop rsi
    ;pop rbx
    pop rcx


.notifunc:
    ; Save function address to hashpointer table
    stosq ; Save RAX to [RDI]


.allhashesdone:
    pop rdx

;------------------CHECKHASH_END-----------------------

.nextentry:
    add rcx, byte 24

    cmp rcx, rdx
    jb short .sf ; Goto next symbol in library

    jmp short .nextlib ; We are done with this library, go to the next one

;------------------LOADER_END-----------------------






real_entry:
    mov ebp, hashpointers ; Used to reduce the size of function calls and memory accesses

    ; Initialize SDL stuff
    push byte 0x20
    pop rdi
    call [rbp] ; SDL_Init

    mov edi, window_title ; Window title
    mov esi, 0x2FFF0000 ; Center of screen
    mov edx, esi ; Center of screen
    mov ecx, 1280
    mov r8d, 720
    push byte 0x2
    pop r9 ; r9d = 0x2 ; opengl
    call [rbp+8*1] ; SDL_CreateWindow

    test rax, rax
    jz exit


    ; Set rdi to window pointer
    push rax
    pop rdi

    ; Save window pointer for later
    xchg r15, rax

    push byte -1 ; -1 == First available driver
    pop rsi
    push byte 0x2 ; SDL_RENDERER_ACCELERATED
    pop rdx
    call [rbp+8*3] ; SDL_CreateRenderer

    test rax, rax
    jz exit

    xchg r14, rax ; renderer pointer

    ; All done

    xor r13, r13

    mov al, 15 ; Just used to save some bytes

    ; Set ball size
    mov [rbp-8], al
    mov [rbp-4], al

    ; left pad init
    mov [rbp-56], byte 35   ; x pos
    mov [rbp-52], byte 50   ; y pos
    mov [rbp-48], al        ; width
    mov [rbp-44], byte 90   ; height

    ; right pad init
    mov [rbp-40], word 1230 ; x pos
    mov [rbp-36], byte 50   ; y pos
    mov [rbp-32], al        ; width
    mov [rbp-28], byte 90   ; height


reset:
    rdrand eax
    jnc short reset ; Repeat until we get a random number

    push byte 5
    pop rdx
    mov ebx, edx

    cmp al, 128
    ja short .right

    neg edx


.right:
    mov dword [rbp-24], edx ; ball_vec X speed

    shr eax, 8
    cmp al, 128
    ja short .up

    neg ebx

.up:
    mov dword [rbp-20], ebx ; ball_vec Y speed
    mov dword [rbp-16], 640 ; ball_vec X position
    mov dword [rbp-12], 360 ; ball_vec Y position

main_loop:
.next_event:
    lea edi, [rbp-120] ; Address of Event buffer
    call [rbp+8*4] ; SDL_PollEvent

    test rax, rax
    jz short .no_more_events

    ; If this is not Zero it means this event is a repeat of a previous event. Ignore it.
    ; Aka holding down a button or something like that
    cmp byte [rbp-107], 1
    jz short .next_event

    mov eax, dword [rbp-120] ; Event type
    cmp ax, 0x100 ; Exit event
    jz exit

    cmp ax, 0x301 ; Key up event
    jz short .zero_r13

    add eax, dword [rbp-104] ; Add which button was it was

    cmp ax, 0x351 ; Key down event + down arrow
    jz short .movedown

    cmp ax, 0x352 ; Key down event + up arrow
    jnz short .next_event

.moveup:
    sub r13d, byte 10

.movedown:
    add r13d, byte 5

    jmp short .next_event

.zero_r13:
    xor r13, r13
    jmp short .next_event


.no_more_events:
    ; Update position of all objects and stuff
    add [rbp-52], r13d ; Update left pad position

    ; Update position of right pad
    mov eax, [rbp-12] ; ball_recty
    sub eax, byte 38 ; Center of right pad
    cmp dword [rbp-36], eax
    push byte 5
    pop rax
    jb short .cont

    neg eax

.cont:
    add dword [rbp-36], eax ; right pad y pos

    ; Update ball position
    mov eax, [rbp-24] ; x speed
    mov ebx, [rbp-20] ; y speed

    ; This is required in the function call further down
    lea esi, [rbp-16] ; ball_rect ; Rect B

    add dword [rsi], eax
    add dword [rsi+4], ebx

    ; Left side
    cmp dword [rsi], byte 0
    jb reset

    ; Right side
    cmp dword [rsi], 1265
    ja reset

    ; Top
    cmp dword [rsi+4], byte 0
    jb short .flip_y

    ; Bottom
    cmp dword [rsi+4], 705
    ja short .flip_y

    ; Left paddle
    lea edi, [rbp-56] ; pad_left_rect
    call [rbp+8*12] ; SDL_HasIntersection

    test rax, rax
    jnz short .flip_xl


    ; Right paddle
    add edi, byte 16 ; pad_right_rect
    call [rbp+8*12] ; SDL_HasIntersection

    test rax, rax
    jnz short .flip_xr

    jmp short .draw_screen


.flip_y:
    neg dword [rbp-20]
    jmp short .draw_screen

.flip_xl:
    sub dword [rbp-24], byte 1
.flip_xr:
    neg dword [rbp-24]



.draw_screen:

    ; Clear screen
    mov rdi, r14 ; renderer pointer
    xor rsi, rsi ; red
    xor rdx, rdx ; green
    xor rcx, rcx ; blue
    push byte -1
    pop r8 ; alpha = 255
    call [rbp+8*5] ; SDL_SetRenderDrawColor

    mov rdi, r14 ; Potentially removable
    call [rbp+8*6] ; SDL_RenderClear



    ; Draw ball rectangle
    mov rdi, r14
    push byte 100
    pop rsi ; red = 100
    mov r8d, edx ; edx is 0xFF for some reason ; alpha = 255
    push byte -107 ; aka 149
    pop rdx ; green = 149
    push byte -19 ; aka 237
    pop rcx ; blue = 237
    call [rbp+8*5] ; SDL_SetRenderDrawColor

    mov rdi, r14 ; Potentially removable
    lea esi, [rbp-16] ; ball_rect
    call [rbp+8*10] ; SDL_RenderFillRect



    ; Draw paddle rectangles
    mov rdi, r14
    lea esi, [rbp-56] ; pad_left_rect
    call [rbp+8*10] ; SDL_RenderFillRect

    mov rdi, r14 ; Potentially removable
    lea esi, [rbp-40] ; pad_right_rect
    call [rbp+8*10] ; SDL_RenderFillRect


    mov rdi, r14 ; Potentially removable
    call [rbp+8*7] ; SDL_RenderPresent


    push byte 16
    pop rdi
    call [rbp+8*11] ; SDL_Delay

    jmp main_loop



exit:
    mov rdi, r14
    call [rbp+8*8] ; SDL_DestroyRenderer

    mov rdi, r15
    call [rbp+8*9] ; SDL_DestroyWindow

    call [rbp+8*2] ; SDL_Quit


    xor edi, edi
    push byte 60 ; exit syscall
    pop rax
    syscall


section .data align=1

window_title:       db `sPong\0`

; This is used to store the hashes of the functions I want
hashtable:
    db 0xFD, 0x09, 0x01, 0xF1 ; SDL_Init:
    db 0xA1, 0xFF, 0xF2, 0x5F ; SDL_CreateWindow:
    db 0x5D, 0x38, 0x46, 0xC6 ; SDL_Quit:
    db 0xA1, 0xF9, 0xC0, 0xE5 ; SDL_CreateRenderer:
    db 0xB6, 0x3A, 0xE9, 0xC3 ; SDL_PollEvent:
    db 0x8D, 0x57, 0x36, 0x3B ; SDL_SetRenderDrawColor:
    db 0xAD, 0xD4, 0xB0, 0x5C ; SDL_RenderClear:
    db 0xBD, 0xAD, 0xE9, 0x99 ; SDL_RenderPresent:
    db 0x38, 0x8F, 0x99, 0x56 ; SDL_DestroyRenderer:
    db 0x69, 0xB5, 0xAA, 0xE3 ; SDL_DestroyWindow:
    db 0x8D, 0x4F, 0x8E, 0x0B ; SDL_RenderFillRect
    db 0x56, 0x82, 0x95, 0x20 ; SDL_Delay
    db 0xF3, 0x2C, 0x1E, 0xFC ; SDL_HasIntersection
    ;dd 0 ; hashtable end; this is needed, however, the memory after this is all zeroes so we can use that


end_of_file:


section .bss
event: resb 64

pad_left_rect:
    resd 1 ; x location
pad_left_y:
    resd 1 ; y location
    resd 1 ; width
    resd 1 ; height

pad_right_rect:
    resd 1 ; x location
pad_right_y:
    resd 1 ; y location
    resd 1 ; width
    resd 1 ; height

ball_vec:   resq 1

ball_rect:  resq 2

; This is used to store the pointers to all the functions
hashpointers:
    SDL_Init:                     resq 1
    SDL_CreateWindow:             resq 1
    SDL_Quit:                     resq 1
    SDL_CreateRenderer:           resq 1
    SDL_PollEvent:                resq 1
    SDL_SetRenderDrawColor:       resq 1
    SDL_RenderClear:              resq 1
    SDL_RenderPresent:            resq 1
    SDL_DestroyRenderer:          resq 1
    SDL_DestroyWindow:            resq 1
    SDL_RenderFillRect:           resq 1
    SDL_Delay:                    resq 1
    SDL_HasIntersection:          resq 1
hashpointers_end:


end_of_bss:
