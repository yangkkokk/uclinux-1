/*
 *  linux/arch/arm/kernel/head-common.S
 *
 *  Copyright (C) 1994-2002 Russell King
 *  Copyright (c) 2003 ARM Limited
 *  All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 */

#define ATAG_CORE 0x54410001
#define ATAG_CORE_SIZE ((2*4 + 3*4) >> 2)
#define ATAG_CORE_SIZE_EMPTY ((2*4) >> 2)

	.align	2
	.type	__switch_data, %object
__switch_data:
	.long	__mmap_switched
	.long	__data_loc			@ r4
	.long	_data				@ r5
	.long	__bss_start			@ r6
	.long	_end				@ r7
	.long	processor_id			@ r4
	.long	__machine_arch_type		@ r5
	.long	__atags_pointer			@ r6
#ifdef CONFIG_CPU_CP15
	.long	cr_alignment			@ r7
#else
	.long	0				@ r7
#endif
	.long	init_thread_union + THREAD_START_SP @ sp

/*
 * The following fragment of code is executed with the MMU on in MMU mode,
 * and uses absolute addresses; this is not position independent.
 *
 *  r0  = cp#15 control register
 *  r1  = machine ID
 *  r2  = atags pointer
 *  r9  = processor ID
 */
__mmap_switched:
	adr	r3, __switch_data + 4

	ldmia	r3!, {r4, r5, r6, r7}
	cmp	r4, r5				@ Copy data segment if needed
1:	cmpne	r5, r6
	ldrne	fp, [r4], #4
	strne	fp, [r5], #4
	bne	1b

	mov	fp, #0				@ Clear BSS (and zero fp)
1:	cmp	r6, r7
	strcc	fp, [r6],#4
	bcc	1b

 ARM(	ldmia	r3, {r4, r5, r6, r7, sp})
 THUMB(	ldmia	r3, {r4, r5, r6, r7}	)
 THUMB(	ldr	sp, [r3, #16]		)

	str	r9, [r4]			@ Save processor ID
	str	r1, [r5]			@ Save machine type
	str	r2, [r6]			@ Save atags pointer
	bic	r4, r0, #CR_A			@ Clear 'A' bit

#if defined(CONFIG_ARCH_M2S)

	/*
	 * For SmartFusion2, we must deal with cache management this early
	 * because kernel_start resides in the cached DDR address alias.
	 * Hence, need to remap the DDR and enable the cache and the
	 * cached address region prior to jumping to kernel_start.
	 */
#if defined(CONFIG_M2S_CACHE)

	/*
	 * Enable caching for the 3rd 128MB region (and disable for
	 * anything else). This corresponds to 0x10000000 - 0x18000000.
	 */
	ldr	r9, =cc_region_cr
	ldr	r9, [r9]
	mov	r1, #0x4
	str	r1, [r9]

	/*
	 * Enable the cache, in case it is still off
	 */
	ldr	r9, =cc_cr
	ldr	r9, [r9]
	mov	r1, #0x1
	str	r1, [r9]

	/*
	 * Flush the cache
	 */
	ldr	r9, =flush_cr
	ldr	r9, [r9]
	ldr	r1, =one_ff
	ldr	r1, [r1]
	str	r1, [r9]
	mov	r1, #0x0
	str	r1, [r9]

	/*
	 * Allow DDR to be aliased into the cacheable region.
	 * DDR will now be visible via two aliases:
	 * - 0xA0000000 (non-cached - used for read-write data)
	 * - 0x10000000 (cached - used for code)
	 */
	ldr	r9, =ddr_cr
	ldr	r9, [r9]
	mov	r1, #0x1
	str	r1, [r9]

#else

	/*
	 * Disable the cache, just in case it was enabled by firmware
	 */
	ldr	r9, =cc_cr
	ldr	r9, [r9]
	mov	r1, #0x0
	str	r1, [r9]
#endif
#endif

	/*
	 * r7 is set to 0 in __switch_data for ARMv7 (conditional on
	 * CONFIG_CPU_CP15. Not surprisingly an attempt to write to 0
	 * in the command below results in an exception on the A2F
	 * (where 0x00000000 is reserved for the internal Flash).
	 * ... Not sure how this code worked on the other ARMv7 platforms.
         */
#ifdef CONFIG_CPU_CP15
	stmia	r7, {r0, r4}			@ Save control register values
#endif
	b	start_kernel

#if defined(CONFIG_ARCH_M2S)
cc_cr:
	.word	0x40038018
#if defined(CONFIG_M2S_CACHE)
cc_region_cr:
	.word	0x4003801c
ddr_cr:
	.word	0x40038008
flush_cr:
	.word	0x400381A8
one_ff:
	.word	0x1FF
#endif
#endif

ENDPROC(__mmap_switched)

/*
 * Exception handling.  Something went wrong and we can't proceed.  We
 * ought to tell the user, but since we don't have any guarantee that
 * we're even running on the right architecture, we do virtually nothing.
 *
 * If CONFIG_DEBUG_LL is set we try to print out something about the error
 * and hope for the best (useful if bootloader fails to pass a proper
 * machine ID for example).
 */
__error_p:
#ifdef CONFIG_DEBUG_LL
	adr	r0, str_p1
	bl	printascii
	mov	r0, r9
	bl	printhex8
	adr	r0, str_p2
	bl	printascii
	b	__error
str_p1:	.asciz	"\nError: unrecognized/unsupported processor variant (0x"
str_p2:	.asciz	").\n"
	.align
#endif
ENDPROC(__error_p)

__error_a:
#ifdef CONFIG_DEBUG_LL
	mov	r4, r1				@ preserve machine ID
	adr	r0, str_a1
	bl	printascii
	mov	r0, r4
	bl	printhex8
	adr	r0, str_a2
	bl	printascii
	adr	r3, 4f
	ldmia	r3, {r4, r5, r6}		@ get machine desc list
	sub	r4, r3, r4			@ get offset between virt&phys
	add	r5, r5, r4			@ convert virt addresses to
	add	r6, r6, r4			@ physical address space
1:	ldr	r0, [r5, #MACHINFO_TYPE]	@ get machine type
	bl	printhex8
	mov	r0, #'\t'
	bl	printch
	ldr     r0, [r5, #MACHINFO_NAME]	@ get machine name
	add	r0, r0, r4
	bl	printascii
	mov	r0, #'\n'
	bl	printch
	add	r5, r5, #SIZEOF_MACHINE_DESC	@ next machine_desc
	cmp	r5, r6
	blo	1b
	adr	r0, str_a3
	bl	printascii
	b	__error
ENDPROC(__error_a)

str_a1:	.asciz	"\nError: unrecognized/unsupported machine ID (r1 = 0x"
str_a2:	.asciz	").\n\nAvailable machine support:\n\nID (hex)\tNAME\n"
str_a3:	.asciz	"\nPlease check your kernel config and/or bootloader.\n"
	.align
#endif

__error:
#ifdef CONFIG_ARCH_RPC
/*
 * Turn the screen red on a error - RiscPC only.
 */
	mov	r0, #0x02000000
	mov	r3, #0x11
	orr	r3, r3, r3, lsl #8
	orr	r3, r3, r3, lsl #16
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
	str	r3, [r0], #4
#endif
1:	mov	r0, r0
	b	1b
ENDPROC(__error)


/*
 * Read processor ID register (CP#15, CR0), and look up in the linker-built
 * supported processor list.  Note that we can't use the absolute addresses
 * for the __proc_info lists since we aren't running with the MMU on
 * (and therefore, we are not in the correct address space).  We have to
 * calculate the offset.
 *
 *	r9 = cpuid
 * Returns:
 *	r3, r4, r6 corrupted
 *	r5 = proc_info pointer in physical address space
 *	r9 = cpuid (preserved)
 */
__lookup_processor_type:
	adr	r3, 3f
	ldmia	r3, {r5 - r7}
	add	r3, r3, #8
	sub	r3, r3, r7			@ get offset between virt&phys
	add	r5, r5, r3			@ convert virt addresses to
	add	r6, r6, r3			@ physical address space
1:	ldmia	r5, {r3, r4}			@ value, mask
	and	r4, r4, r9			@ mask wanted bits
	teq	r3, r4
	beq	2f
	add	r5, r5, #PROC_INFO_SZ		@ sizeof(proc_info_list)
	cmp	r5, r6
	blo	1b
	mov	r5, #0				@ unknown processor
	b	__error
2:	mov	pc, lr
ENDPROC(__lookup_processor_type)

/*
 * This provides a C-API version of the above function.
 */
ENTRY(lookup_processor_type)
	stmfd	sp!, {r4 - r7, r9, lr}
	mov	r9, r0
	bl	__lookup_processor_type
	mov	r0, r5
	ldmfd	sp!, {r4 - r7, r9, pc}
ENDPROC(lookup_processor_type)

/*
 * Look in <asm/procinfo.h> and arch/arm/kernel/arch.[ch] for
 * more information about the __proc_info and __arch_info structures.
 */
	.align	2
3:	.long	__proc_info_begin
	.long	__proc_info_end
4:	.long	.
	.long	__arch_info_begin
	.long	__arch_info_end

/*
 * Lookup machine architecture in the linker-build list of architectures.
 * Note that we can't use the absolute addresses for the __arch_info
 * lists since we aren't running with the MMU on (and therefore, we are
 * not in the correct address space).  We have to calculate the offset.
 *
 *  r1 = machine architecture number
 * Returns:
 *  r3, r4, r6 corrupted
 *  r5 = mach_info pointer in physical address space
 */
__lookup_machine_type:
	adr	r3, 4b
	ldmia	r3, {r4, r5, r6}
	sub	r3, r3, r4			@ get offset between virt&phys
	add	r5, r5, r3			@ convert virt addresses to
	add	r6, r6, r3			@ physical address space
1:	ldr	r3, [r5, #MACHINFO_TYPE]	@ get machine type
	teq	r3, r1				@ matches loader number?
	beq	2f				@ found
	add	r5, r5, #SIZEOF_MACHINE_DESC	@ next machine_desc
	cmp	r5, r6
	blo	1b
	mov	r5, #0				@ unknown machine
2:	mov	pc, lr
ENDPROC(__lookup_machine_type)

/*
 * This provides a C-API version of the above function.
 */
ENTRY(lookup_machine_type)
	stmfd	sp!, {r4 - r6, lr}
	mov	r1, r0
	bl	__lookup_machine_type
	mov	r0, r5
	ldmfd	sp!, {r4 - r6, pc}
ENDPROC(lookup_machine_type)

/* Determine validity of the r2 atags pointer.  The heuristic requires
 * that the pointer be aligned, in the first 16k of physical RAM and
 * that the ATAG_CORE marker is first and present.  Future revisions
 * of this function may be more lenient with the physical address and
 * may also be able to move the ATAGS block if necessary.
 *
 * r8  = machinfo
 *
 * Returns:
 *  r2 either valid atags pointer, or zero
 *  r5, r6 corrupted
 */
__vet_atags:
	tst	r2, #0x3			@ aligned?
	bne	1f

	ldr	r5, [r2, #0]			@ is first tag ATAG_CORE?
	cmp	r5, #ATAG_CORE_SIZE
	cmpne	r5, #ATAG_CORE_SIZE_EMPTY
	bne	1f
	ldr	r5, [r2, #4]
	ldr	r6, =ATAG_CORE
	cmp	r5, r6
	bne	1f

	mov	pc, lr				@ atag pointer is ok

1:	mov	r2, #0
	mov	pc, lr
ENDPROC(__vet_atags)

/*
 * Copy the romfs to the end of "_end" segment.
 *
 *  __romfsinfo
 *		.long <RomFS start address in ROM>
 *		.long <RomFS start address in RAM>
 */

#if defined(CONFIG_MTD_UCLINUX) && defined(CONFIG_MTD_UCLINUX_RELOCATE)
	.align	2
	.type	__romfsinfo, %object
__romfsinfo:
	.long	CONFIG_MTD_UCLINUX_PHYADDR	@ r6 RomFS start dddress
	.long	_end				@ r7 Kernel end address. This is used in "uclinuc.c"

__relocate_romfs:
	adr 	r4, __romfsinfo
	ldmia	r4!, {r6, r7}

	/*
	 * Move the ram based rom filesystem to its correct final location
	 */
	mov 	fp, #0
	add 	r4, r6, #8
	ldrb 	r4, [r4]
	orr 	fp, fp, r4, lsl #24
	add 	r4, r6, #9
	ldrb 	r4, [r4]
	orr 	fp, fp, r4, lsl #16
	add 	r4, r6, #10
	ldrb 	r4, [r4]
	orr 	fp, fp, r4, lsl #8
	add 	r4, r6, #11
	ldrb 	r4, [r4]
	orr 	fp, fp, r4, lsl #0 		@ fp = romfs_size
	ldr     r4, =0x000fffff			@ 1 MB boundary mask
	and     fp, fp, r4			@ 1 MB romfs boundary
	add 	r4, r6, fp			@ r4 = src_end-4
	sub 	r4, r4, #4
	add 	fp, r7, fp			@ fp = dst_end-4
	sub 	fp, fp, #4
1: 	ldr 	r5, [r4]
	str 	r5, [fp]
	sub 	r4, r4, #4
	sub 	fp, fp, #4
	cmp 	r4, r6
	bne 	1b
	ldr 	r5, [r4]			@ read last byte from src
	str 	r5, [fp]			@ write last byte to the dst
	mov 	pc, lr
ENDPROC(__relocate_romfs)
#endif


/*
 * Copy the ".init_data" section data from ROM to RAM
 * and clear ".bss" section.
 *
 *  __section_bss
 *		.long <".bss" section start address in RAM>
 *		.long <".bss" section end   address in RAM>
 *
 *  __section_data
 *		.long <Data section start address in ROM>
 *		.long <Data section end   address in ROM>
 *		.long <Data section start address in RAM>
 */

#ifdef CONFIG_XIP_KERNEL
	.align	2

	.type	__section_bss, %object
__section_bss:
	.long	__bss_start			@ r6 ".bss" section start address
	.long	__bss_stop			@ r7 ".bss" section end   address

	.type	__section_data, %object
__section_data:
	.long	__data_loc			@ r6 data section start address in ROM
	.long	_edata_loc			@ r7 data section end   address in ROM
	.long	_sdata				@ r8 data section start address in RAM

__relocate_xipdata:

	/*
	 * Copy the ".init_data" section data from ROM to RAM location
	 */
	adr 	r4, __section_data
	ldmia	r4!, {r6, r7, r8}
1: 	ldr 	r5, [r6]
	str 	r5, [r8]
	add 	r6, r6, #4
	add 	r8, r8, #4
	cmp 	r6, r7
	bne 	1b

	/*
	 * Clear the ".bss" section data in RAM location
	 */
	adr 	r4, __section_bss
	ldmia	r4!, {r6, r7}
	mov 	fp, #0
2: 	str 	fp, [r6]
	add 	r6, r6, #4
	cmp 	r6, r7
	bne 	2b
	mov 	pc, lr
ENDPROC(__relocate_xipdata)
#endif
