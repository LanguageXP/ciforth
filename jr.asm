  
 .org 07c00h             # This means we'll have to trim the
 			#    binary with dd or something. Well worth it.
 			#    After   as   and   objcopy -O binary   do
 			#    dd < a.out > whatever bs=512 skip=62
  
 BITS 16
 .global _start
_start:
  
 cli	;
  
 movw $gdt_entries , %si	# copy initial GDT descriptors to  x2000
 movw $02008h , %di              #       skip and thus allocate entry 0
 mov %di , %bx
 add $0100h , %bx
for_128_duals:                  # move 256 bytes
 	mov  (%si) , %ax
 	mov  %ax, %es:(%di)
 	add $2 , %di
 	add $2 , %si
 	cmp %bx , %di
 jnz for_128_duals
 				# 	assuming %es=0 and ss makes sense.
 				#	My P166 BIOS allows this. YMMV.
  
 lgdt initial_gdtr		# This is one reason for the .org 07c00
  
 movh %cr0 , %ecx
 inc %cx
 mov %ecx , %cr0		# protection is on, but we need to get into
 				# 32 bit segments. You have to branch to
 				# a new cs, mov won't do cs.
  
 				# hand assembled jmp sd1:cs32
 DB   066h                    # we're still IN 16 bit
 DB   0eah
 .long   cs32
 DW   008h                    # 8 is GDT index 1, our code seg. selector
  
cs32:
  
 BITS 32                 # since we just jumped to a 32 bit segment
  
 mov $010h , %eax                # selector 010h is index 2, our 32 bit data
 movw %ax , %ds
 movw %ax , %ss			# This might help with the 32/16/32 stunts.
  
 mov $09000h , %esp              # first 64k of second meg is our stack
  
 #
 ## BUILD Interrupt Descriptor Table at 01000h physical
 #	256 interrupt gate descriptors that call sequential IIT
 #	calls, which all call INTCALLER.
  
 movw $07003h , %eax
 movl $01000h , %edi
per_IDT_descriptor:                     # Our first (example) entry is...
 	movw %eax , (%edi)		# 03 70       starting at 01000h 
 	inc %edi			# offset
 	inc %edi
 	movw $008h , (%edi)
 	inc %edi			# 03 70 	08 00
 	inc %edi			# 		pmode code sel.
 	movl $000008e00h , (%edi)
 	inc %edi			# 03 70 20 00 	00 8e 00 00
 	inc %edi			# 		present    intrrgate
 	inc %edi
 	inc %edi
 	add $8 , %eax
 	cmp $07803h, %eax
 jnz per_IDT_descriptor
  
 lidt initial_idtr
  
 #
 ## BUILD Int Indirection Table at 07000h <-> 07800.h This is a bunch of
 #	calls that INTCALLER can pop the return address of to find out
 #	what int is happening.
  
 mov	$0ffh , %ebx
 mov 	$07000h , %edi
 mov	$(INTCALLER - 07008h )  , %eax           # first relative offset
 						# byte following
while_B:
 		# dest is cursor into IIT
 		# eax is current call offset
 		# ebx is an entry counter, and is extraneous
  
 	movl	$0e8909090h , (%edi)    # e8 opcode for CALL rel32
 					# prefixed with NOPs. Note endianism.
 	add $4 ,  %edi
 	movl	%eax , (%edi)		# append 4 byte relative offset
 	add $4 ,  %edi
 	subl	$8, %eax			# relative offset from next IIT call to
 					# INTCALLER will be 8 less.
 	dec %ebx
 jnz while_B
  
 sti	;
  
HANG: nop  ;
  
 	mov  0b8060h , %eax
 	inc %eax
 	inc %eax
 	mov %eax , 0b8060h 
 	int $040h 
  
 jmp HANG ###########
 #################################
  
INTCALLER:              # System code, so to speak.
  
 			# we are in the system 32-bit segments
  
 mov %eax , 06300
 poph %eax                        # gotta pop the I.I.T. return value to calculate
 			#   which int we are.
  
  mov  0b8060h + 320 , %eax
  inc %eax
  inc %eax
  mov %eax , 0b8060h +320
  
 DB   0eah                    # far jmp to a suitable-for-real-mode cs
 .long	small_code_segment
 DW   020
small_code_segment:             #h we are a 16-bit machine with no useful
 				# 	segments.
  
 BITS 16
  
 movl $018h , %eax                       # upgrade to an 8086
  
 movw %eax , %ds
 movw %eax , %ss
  
 mov %cr0 , %ecx
 dec %cx
 mov %ecx , %cr0		# turn off protection, losing the segments
 				# 	again.
  
 DB   0eah 
 DW   rereal
 DW   00h                     # far jmp to an 8086 cs, NOT a dscriptor
  
rereal:
  
 mov $0b800h , %ax               # real mode demo code. This, I think, could be
 mov %ax , %ds			#   an 8086 int caller, which is
 mov 06400h , %ax
 sub $1, %ax			#   Left as an Excercize to the Reader.
 mov %ax , 1620			#   HINT:  pushf
 mov %ax , 06400h 
  
 mov %cr0 , %ecx
 inc %ecx
 mov %ecx , %cr0
  
 DB   0eah 
 DW   recs32
 DW   008h                    # 8 is GDT index 1, our code seg. selector
  
recs32:
  
 BITS 32
  
 movw $010h , %eax
  
 mov %eax , %ds
 mov %eax , %ss
  
  mov  0b8060h + 640 , %eax
  inc %eax
  inc %eax
  mov %eax , 0b8060h +640
  
 iret
  
 ############### initialized DATA allocations      ####################
  
gdt_entries:
 	# The GDT copy routine skip-allocates index 0.
 	# We initialize from index 1 on. Index 1 = selector 8.
 	# This template is for typical segments, not gates and such.
  
         DW   0FFFFh  # low dual of limit
 	DW   0       # low dual of base
 	DB   0       # bits 16<->23 of base
  
 				# The DFbyte, see also the DFnybble
 				#
 				# bit	on=	description	  bit of 64
 				# 0	01h     accessed                40
 				# 1	02h     read/write              41
 				# 2	04h     expandup/conform        42
 				# 3	08h     executable?             43
 				# 4	010h    typical                 44
 				# 5	020h    DPL lo                  45
 				# 6	040h    DPL hi                  46
 				# 7	080h    present                 47
 	DB   09Ah    # = present typical executable readable
  
 				# bit	on=     description	  bit of 64
                                 # 0	01h     limit hi nybble         48
                                 # 1     02h             "               49
                                 # 2     04h             "               50
                                 # 3     08h             "               51
 				# The DFnybble(TM)
 				# 4     010h    AVL                     52
                                 # 5     020h    0                       53
                                 # 6     040h    Big/D-efault/X          54
 				# D-bit true = 32 bit addy/operands in pmode
                                 # 7     080h    4k Granularity          55
 	DB   0CFh    # = *4k Big   f-nybble
 	DB   000h    # hi byte of base
  
 # index 2, 32 bit data, selector val = 010,h 4 gig limit, 0 base
         DW   0FFFFh 
 	DW   0
 	DB   000
 	DBh   092h    # present typical writable
 	DB   0cfh    # *4k  BIG  f-nybble
 	DB   000h
  
 # index 3, 16 bit data, selector val = 018,h 64k limit, 0 base
         DW   0FFFFh  # limit
         DW   0
         DB   0
         DB   092h    # present typical writable
         DB   00h     # (bytegrain) 0-max-nybble-of-limit
         DB   0
  
 # index 4, 16 bit code, selector val = 020,h 64k lim/gran, 0000 base
 # this is base 0 real-ish, for INTCALLER , ffff limit
  
         DW   0FFFFh  # limit
         DW   0       # this is physical
 	DB   00h     #     this OR previous dual = 0000
 	DB   09ah    # present typical executable readable
 	DB   00h     # (smallgrain) (notBIG) 0-max-nybble-of-limit
         DB   0
  
 #,.....................................................
  
 ## 6 byte limits/pointers for IDTR & GDTR
  
initial_idtr:
 	DW  0800h            # 2k, 256 * 8
 	.long  01000h           # gdt physical address
  
initial_gdtr:
 	DW  0400h            # gdt limit
 	.long  02000h           # gdt physical address
  
 .org 07dfeh
 DW  0AA55h   # Claim to be a PEEEEEEE.CEE bootsector.
  
STAGE_II:
 # get a floppy load on, put your OS here, and jmp here.
  
 # Copyright 2000 Rick Hohensee
 # References/keys: Intel 386 manuals, John Fine, GNU as.info, gazos
 #	Ralf Brown's, Linux
 # Janet_Reno.s
