#!/usr/bin/env python3
"""Backward-compatible entry point for partial Qnet generation.

Historically this workflow called the partial model-fitting step 'inferqnet'.
All arguments are handled by createLSM.py, including the old aliases
-file/-begin/-end/-alpha/-prefix.
"""
from createLSM import main

if __name__ == "__main__":
    main()
