# syntax=docker/dockerfile:1

# ---- Build stage --------------------------------------------------------
# Full Haskell toolchain (GHC 9.6.7 + cabal) matching the project's base ^>=4.18.3.0.
FROM haskell:9.6.7 AS build
WORKDIR /app

# Copy only the cabal file first so the dependency layer is cached and only
# rebuilt when mini-brig.cabal changes (not on every source edit).
COPY mini-brig.cabal ./
RUN cabal update && cabal build --only-dependencies --enable-tests

# Copy the rest of the sources and build the project (-Werror applies here).
COPY . .
RUN cabal build

# Run the test-suite as part of the image build: a failing test fails the build.
RUN cabal test

# Stage the executable so the runtime image can grab it without dist-newstyle.
RUN mkdir -p /out && cp "$(cabal list-bin mini-brig)" /out/mini-brig

# ---- Runtime stage ------------------------------------------------------
# Slim Debian with just the shared libs GHC binaries need (gmp, ffi).
FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libgmp10 libffi8 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/mini-brig /usr/local/bin/mini-brig

# Warp listens on 8080 (see app/Main.hs).
EXPOSE 8080
CMD ["mini-brig"]
