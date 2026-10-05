"""Shared semantic key for generated line-break machine categories."""


def category_key(raw, wide=False, pi=False, pf=False, op30=False, cp30=False,
                 ep=False, sa_mark=False, hyphen=False, dotted=False):
    """Return the normalized tuple whose first-scalar order defines category IDs."""
    return (raw.lower(), bool(wide), bool(pi), bool(pf), bool(op30), bool(cp30),
            bool(ep), bool(sa_mark), bool(hyphen), bool(dotted))
