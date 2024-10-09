FROM node:lts as build

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001

# Removing unnecessary files for us
RUN find . -mindepth 1 -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec bash -c 'echo "Deleting {}"; rm -rf {}' \;

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get -y --no-install-recommends install \
        tini

# Copy in Install version of Package.json and install deps for x64 linux deployment env.
WORKDIR /usr/src/app/
COPY --chown=${USER}:${USER} ./install/package.json /usr/src/app/
RUN mkdir custom-plugins
# Uses locally installed version of custom plugin nodebb-plugin-hidden to prevent need for git auth in build process.
COPY --chown=${USER}:${USER} ./node_modules/nodebb-plugin-hidden ./custom-plugins/
RUN npm install --cpu=x64 --os=linux --libc=glibc

FROM node:lts-slim AS final

# TODO: Have docker-compose use environment variables to create files like setup.json and config.json.
COPY --from=hairyhenderson/gomplate:stable /gomplate /usr/local/bin/gomplate

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.17
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
	rm -rf /var/lib/apt/lists/*; \
	arch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	case "$arch" in \
		'amd64') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64'; sha256='bbc4136d03ab138b1ad66fa4fc051bafc6cc7ffae632b069a53657279a450de3' ;; \
		'arm64') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-arm64'; sha256='c3805a85d17f4454c23d7059bcb97e1ec1af272b90126e79ed002342de08389b' ;; \
		'armel') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-armel'; sha256='f9969910fa141140438c998cfa02f603bf213b11afd466dcde8fa940e700945d' ;; \
		'i386') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-i386'; sha256='087dbb8fe479537e64f9c86fa49ff3b41dee1cbd28739a19aaef83dc8186b1ca' ;; \
		'mips64el') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-mips64el'; sha256='87140029d792595e660be0015341dfa1c02d1181459ae40df9f093e471d75b70' ;; \
		'ppc64el') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-ppc64el'; sha256='1891acdcfa70046818ab6ed3c52b9d42fa10fbb7b340eb429c8c7849691dbd76' ;; \
		'riscv64') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-riscv64'; sha256='38a6444b57adce135c42d5a3689f616fc7803ddc7a07ff6f946f2ebc67a26ba6' ;; \
		's390x') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-s390x'; sha256='69873bab588192f760547ca1f75b27cfcf106e9f7403fee6fd0600bc914979d0' ;; \
		'armhf') url='https://github.com/tianon/gosu/releases/download/1.17/gosu-armhf'; sha256='e5866286277ff2a2159fb9196fea13e0a59d3f1091ea46ddb985160b94b6841b' ;; \
		*) echo >&2 "error: unsupported gosu architecture: '$arch'"; exit 1 ;; \
	esac; \
	wget -O /usr/local/bin/gosu.asc "$url.asc"; \
	wget -O /usr/local/bin/gosu "$url"; \
	echo "$sha256 */usr/local/bin/gosu" | sha256sum -c -; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001

WORKDIR /usr/src/app/

RUN corepack enable \
    && groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ --shell /bin/bash ${USER} \
    && mkdir -p /usr/src/app/logs/ /opt/config/ \
    && chown -R ${USER}:${USER} /usr/src/app/ \
    && chown -R ${USER}:${USER} /opt/config/

COPY --from=build --chown=${USER}:${USER} /usr/bin/tini /usr/local/bin/
COPY --from=build --chown=${USER}:${USER} /usr/bin/tini /usr/local/bin/

# this copy from local version ignores node_modules
COPY --chown=${USER}:${USER} . /usr/src/app/
# copy in built node_modules & jsons
COPY --from=build --chown=${USER}:${USER} /usr/src/app/package.json /usr/src/app/
COPY --from=build --chown=${USER}:${USER} /usr/src/app/package-lock.json /usr/src/app/
COPY --from=build --chown=${USER}:${USER} /usr/src/app/node_modules /usr/src/app/

RUN cp /usr/src/app/install/docker/docker-entrypoint.sh /usr/local/bin/ \
    && cp /usr/src/app/install/docker/entrypoint.sh /usr/local/bin/ \
    && cp /usr/src/app/config.json.template /opt/config/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/tini

EXPOSE 4567

VOLUME ["/usr/src/app/public/uploads"]

# Utilising tini as our init system within the Docker container for graceful start-up and termination.
# Tini serves as an uncomplicated init system, adept at managing the reaping of zombie processes and forwarding signals.
# This approach is crucial to circumvent issues with unmanaged subprocesses and signal handling in containerised environments.
# By integrating tini, we enhance the reliability and stability of our Docker containers.
# Ensures smooth start-up and shutdown processes, and reliable, safe handling of signal processing.
ENTRYPOINT ["tini", "--", "docker-entrypoint.sh"]