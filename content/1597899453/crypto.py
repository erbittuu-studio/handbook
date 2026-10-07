#!/usr/bin/env python3
"""Shared encrypt/decrypt for published packs — copied into every app,
byte-identical, like build.py.

Key = SHA-256 of the app's own App Store id (the folder name this file
lives in). Every app already knows its own id, so nothing extra needs to be
stored in it to compute the same key back.

This is a light deterrent against casual scraping of the hosted repo — it
stops someone browsing GitHub from reading packs directly, and RawPacks/
(the plaintext source) is never pushed at all (see .gitignore), so the repo
never has a readable copy of the content sitting next to the encrypted one.
It does not stop someone who reverse-engineers the compiled app itself;
nothing can — the app has to be able to decrypt its own downloads, so a
determined attacker with the binary in hand always can too.
"""
import hashlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def derive_key(app_store_id: str) -> bytes:
    return hashlib.sha256(app_store_id.encode()).digest()


def encrypt(plaintext: bytes, app_store_id: str) -> bytes:
    """nonce(12) + ciphertext + tag(16) — one self-contained blob.

    The nonce is derived from the plaintext itself, not random, so identical
    content always encrypts to identical bytes — unchanged packs keep their
    hash and aren't re-uploaded, same as before encryption existed.
    """
    key = derive_key(app_store_id)
    nonce = hashlib.sha256(plaintext).digest()[:12]
    return nonce + AESGCM(key).encrypt(nonce, plaintext, None)


def decrypt(blob: bytes, app_store_id: str) -> bytes:
    key = derive_key(app_store_id)
    nonce, ciphertext = blob[:12], blob[12:]
    return AESGCM(key).decrypt(nonce, ciphertext, None)
