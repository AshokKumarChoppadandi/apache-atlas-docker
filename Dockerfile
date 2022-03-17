# ------------------------------ ATLAS CODE COMPILE STAGE ------------------------------
FROM maven:3.8.4-openjdk-8 AS atlas_compile

LABEL maintainer="Hritvik Patel <hritvik.patel4@gmail.com>"

ENV ATLAS_VERSION 2.2.0

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install apt-utils patch python && \
    cd /tmp && \
    wget --retry-connrefused -O apache-atlas-$ATLAS_VERSION-sources.tar.gz https://downloads.apache.org/atlas/$ATLAS_VERSION/apache-atlas-$ATLAS_VERSION-sources.tar.gz && \
    mkdir -p /tmp/atlas-src && \
    tar xzf /tmp/apache-atlas-$ATLAS_VERSION-sources.tar.gz -C /tmp/atlas-src --strip 1 && \
    rm -rf /tmp/apache-atlas-$ATLAS_VERSION-sources.tar.gz

COPY patches/* /tmp/atlas-src

RUN cd /tmp/atlas-src && \
    patch -u -b pom.xml -i log4j.patch && \
    patch -u -b webapp/src/main/java/org/apache/atlas/web/filters/AtlasAuthenticationFilter.java -i deprecateNDC.patch && \
    rm log4j.patch && \
    rm deprecateNDC.patch && \
    sed -i "s/http:\/\/repo1.maven.org\/maven2/https:\/\/repo1.maven.org\/maven2/g" pom.xml && \
    export MAVEN_OPTS="-Xms2g -Xmx4g" && \
    mvn clean -Dhttps.protocols=TLSv1.2 package -Pdist
    # Add option '-DskipTests' to skip unit and integration tests
    # mvn clean -Dhttps.protocols=TLSv1.2 -DskipTests package -Pdist

# ------------------------------ ATLAS IMAGE CREATION STAGE ------------------------------
FROM ubuntu:bionic

LABEL maintainer="Hritvik Patel <hritvik.patel4@gmail.com>"

ENV ATLAS_VERSION 2.2.0
ENV ATLAS_INSTALL_LOCATION /opt/apache-atlas-$ATLAS_VERSION
ENV HADOOP_VERSION 2.7.3
ENV HIVE_VERSION 2.3.6

COPY --from=atlas_compile /tmp/atlas-src/distro/target/apache-atlas-$ATLAS_VERSION-hive-hook.tar.gz /tmp
COPY --from=atlas_compile /tmp/atlas-src/distro/target/apache-atlas-$ATLAS_VERSION-kafka-hook.tar.gz /tmp
COPY --from=atlas_compile /tmp/atlas-src/distro/target/apache-atlas-$ATLAS_VERSION-server.tar.gz /tmp

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y install curl openjdk-8-jdk patch python unzip && \
    apt-get -y autoclean && \
    curl -o /tmp/hadoop-$HADOOP_VERSION.tar.gz        https://archive.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz && \
    curl -o /tmp/apache-hive-$HIVE_VERSION-bin.tar.gz https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz && \
    tar xzf /tmp/hadoop-$HADOOP_VERSION.tar.gz                  -C /opt && \
    tar xzf /tmp/apache-hive-$HIVE_VERSION-bin.tar.gz           -C /opt && \
    tar xzf /tmp/apache-atlas-$ATLAS_VERSION-hive-hook.tar.gz   -C /opt && \
    tar xzf /tmp/apache-atlas-$ATLAS_VERSION-kafka-hook.tar.gz  -C /opt && \
    tar xzf /tmp/apache-atlas-$ATLAS_VERSION-server.tar.gz      -C /opt && \
    mkdir -p /apache-atlas-$ATLAS_VERSION && \
    cp /tmp/apache-atlas-$ATLAS_VERSION-hive-hook.tar.gz / && \
    tar xzf apache-atlas-$ATLAS_VERSION-hive-hook.tar.gz -C /apache-atlas-$ATLAS_VERSION --strip 1 && \
    tar czf apache-atlas-$ATLAS_VERSION.tar.gz apache-atlas-$ATLAS_VERSION && \
    cp -R /opt/apache-atlas-hive-hook-$ATLAS_VERSION/*  $ATLAS_INSTALL_LOCATION && \
    cp -R /opt/apache-atlas-kafka-hook-$ATLAS_VERSION/* $ATLAS_INSTALL_LOCATION && \
    mkdir -p $ATLAS_INSTALL_LOCATION/conf/patches && \
    echo $ATLAS_VERSION > $ATLAS_INSTALL_LOCATION/version.txt && \
    rm -rf apache-atlas-$ATLAS_VERSION-hive-hook.tar.gz /apache-atlas-$ATLAS_VERSION && \
    rm -rf /opt/apache-atlas-hive-hook-$ATLAS_VERSION /opt/apache-atlas-kafka-hook-$ATLAS_VERSION && \
    rm -rf /tmp/*
    # rm -rf /var/lib/apt/lists/*

ENV HADOOP_HOME /opt/hadoop-$HADOOP_VERSION
ENV HADOOP_CONF_DIR $HADOOP_HOME/etc/hadoop

ENV HIVE_HOME /opt/apache-hive-$HIVE_VERSION-bin
ENV HIVE_CONF_DIR $HIVE_HOME/conf

ENV HBASE_CONF_DIR $ATLAS_INSTALL_LOCATION/conf/hbase
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

COPY patches/* $ATLAS_INSTALL_LOCATION/conf/patches
COPY conf/* $ATLAS_INSTALL_LOCATION/conf
COPY atlas_stop /
COPY docker_entrypoint.sh /

ENV PATH $PATH:$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin

RUN chmod +x /docker_entrypoint.sh
RUN chmod +x /atlas_stop && mkdir /scripts && mv atlas_stop /scripts

ENV PATH $PATH:/scripts

EXPOSE 21000

VOLUME ["$ATLAS_INSTALL_LOCATION/conf", "$ATLAS_INSTALL_LOCATION/data", "$ATLAS_INSTALL_LOCATION/logs"]

ENTRYPOINT ["/docker_entrypoint.sh"]
