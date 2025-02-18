// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

// Cipher block chaining (CBC) mode.

// CBC provides confidentiality by xoring (chaining) each plaintext block
// with the previous ciphertext block before applying the block cipher.

// See NIST SP 800-38A, pp 10-11

// NOTE this will be moved to crypto.cipher interface (joe-c)

module aes

import (
	crypto.cipher
	crypto.internal.subtle
)

struct AesCbc {
mut:
	b          AesCipher
	block_size int
	iv         []byte
	tmp        []byte
}

fn _new_cbc(b AesCipher, iv []byte) AesCbc {
	return AesCbc{
		b:          b,
		block_size: b.block_size(),
		// TODO: make b.iv copy of iv
		iv:         iv,
		tmp:        [byte(0); b.block_size()],
	}
}

// new_cbc_encrypter returns a BlockMode which encrypts in cipher block chaining
// mode, using the given Block. The length of iv must be the same as the
// Block's block size.
pub fn new_cbc(b AesCipher, iv []byte) AesCbc {
	if iv.len != b.block_size() {
		panic('crypto.cipher.new_cbc_encrypter: IV length must equal block size')
	}
	return _new_cbc(b, iv)
}

pub fn (x &AesCbc) block_size() int { return x.block_size }

pub fn (x &AesCbc) encrypt_blocks(dst, src []byte) {
	if src.len%x.block_size != 0 {
		panic('crypto.cipher: input not full blocks')
	}
	if dst.len < src.len {
		panic('crypto.cipher: output smaller than input')
	}
	if subtle.inexact_overlap(dst.left(src.len), src) {
		panic('crypto.cipher: invalid buffer overlap')
	}

	mut iv := x.iv

	for src.len > 0 {
		// Write the xor to dst, then encrypt in place.
		cipher.xor_bytes(dst.left(x.block_size), src.left(x.block_size), iv)
		x.b.encrypt(dst.left(x.block_size), dst.left(x.block_size))

		// Move to the next block with this block as the next iv.
		iv = dst.left(x.block_size)
		if x.block_size >= src.len {
			src = []byte
		} else {
			src = src.right(x.block_size)
		}
		dst = dst.right(x.block_size)
	}

	// Save the iv for the next crypt_blocks call.
	// TODO: make x.iv a copy of iv
	x.iv = iv
}

pub fn (x &AesCbc) decrypt_blocks(dst, src []byte) {
	if src.len%x.block_size != 0 {
		panic('crypto.cipher: input not full blocks')
	}
	if dst.len < src.len {
		panic('crypto.cipher: output smaller than input')
	}
	if subtle.inexact_overlap(dst.left(src.len), src) {
		panic('crypto.cipher: invalid buffer overlap')
	}
	if src.len == 0 {
		return
	}

	// For each block, we need to xor the decrypted data with the previous block's ciphertext (the iv).
	// To avoid making a copy each time, we loop over the blocks BACKWARDS.
	mut end := src.len
	mut start := end - x.block_size
	mut prev := start - x.block_size

	// Copy the last block of ciphertext in preparation as the new iv.
	// TODO: copy
	x.tmp = src.slice(start, end)

	// Loop over all but the first block.
	for start > 0 {
		x.b.decrypt(dst.slice(start, end), src.slice(start, end))
		cipher.xor_bytes(dst.slice(start, end), dst.slice(start, end), src.slice(prev, start))

		end = start
		start = prev
		prev -= x.block_size
	}

	// The first block is special because it uses the saved iv.
	x.b.decrypt(dst.slice(start, end), src.slice(start, end))
	cipher.xor_bytes(dst.slice(start, end), dst.slice(start, end), x.iv)


	// Set the new iv to the first block we copied earlier.
	x.iv = x.tmp
	x.tmp = x.iv
}

fn (x &AesCbc) set_iv(iv []byte) {
	if iv.len != x.iv.len {
		panic('cipher: incorrect length IV')
	}
	// TODO: make x.iv a copy of iv
	x.iv = iv
}
