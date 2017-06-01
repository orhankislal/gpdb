#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"
source "${CWDIR}/postgis_check_gpdb.bash"

function prep_compile_gpdb(){

  cat > /opt/compile_gpdb.sh <<-EOF

		set -exo pipefail
		base_path=\${1}
		cd /tmp/
		sudo yum -y install git gcc readline-devel zlib-devel libcurl-devel bzip2-devel bison flex gcc-c++ python-devel openssl-devel libffi-devel libapr-devel libevent-devel
		sudo yum -y install perl-ExtUtils-MakeMaker.noarch perl-ExtUtils-Embed.noarch
		sudo yum -y install apr-util-devel libxml2-devel libxslt-devel
		sudo yum -y install wget zip unzip
		curl https://bootstrap.pypa.io/get-pip.py | sudo python
		sudo pip install --upgrade setuptools wheel paramiko pip lockfile epydoc psutil

		wget https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz
		tar -xzvf libevent-2.1.8-stable.tar.gz
		cd libevent-2.1.8-stable
		./configure --prefix=/usr --disable-static
		make
		sudo make install

		cd /tmp/
        wget https://cmake.org/files/v3.8/cmake-3.8.1-Linux-x86_64.tar.gz
        tar -xzvf cmake-3.8.1-Linux-x86_64.tar.gz
        cd cmake-3.8.1-Linux-x86_64/bin
        export CMAKE_HOME=\$(pwd)

		cd /tmp/
        wget https://github.com/greenplum-db/gp-xerces/archive/master.zip
        sudo unzip master.zip
        cd gp-xerces-master
        mkdir build
        cd build
        ../configure --prefix=/usr/local
        make
        sudo make install
        export LDFLAGS='-L/usr/local/lib/'
        export LD_LIBRARY_PATH=/usr/local/lib/:\$LD_LIBRARY_PATH
        cd /tmp/
        sudo rm master.zip

        sudo touch /etc/ld.so.conf.d/test1.conf
        sudo echo "/usr/local/lib" >> /etc/ld.so.conf.d/test1.conf
        sudo ldconfig

        wget https://github.com/greenplum-db/gporca/archive/master.zip
        sudo unzip master.zip
        cd gporca-master/
        mkdir build
        cd build
        /tmp/cmake-3.8.1-Linux-x86_64/bin/cmake ../
        make
        sudo make install
        cd /tmp/
        sudo rm master.zip

		cd \${base_path}/gpdb_src
		./configure --with-libxml --with-libxslt --with-python --with-perl --prefix=/tmp/gpdb-deploy --enable-orca
		make
		sudo make install
		cd \${base_path}


	EOF

	chmod a+x /opt/compile_gpdb.sh
}


function make_cluster() {
  set -exo pipefail
  source /tmp/gpdb-deploy/greenplum_path.sh
  export BLDWRAP_POSTGRES_CONF_ADDONS=${BLDWRAP_POSTGRES_CONF_ADDONS}
  export LDFLAGS='-L/usr/local/lib/'
  export LD_LIBRARY_PATH=/usr/local/lib/:$LD_LIBRARY_PATH
  ldconfig
  # Currently, the max_concurrency tests in src/test/isolation2
  # require max_connections of at least 129.
  export DEFAULT_QD_MAX_CONNECT=150
  workaround_before_concourse_stops_stripping_suid_bits
  pushd gpdb_src/gpAux/gpdemo
	  su gpadmin -c make cluster
  popd
}


function _main() {

	prep_compile_gpdb

	ln -s "$(pwd)/gpdb_src/gpAux/ext/rhel6_x86_64/python-2.7.12" /opt
	su - root -c "bash /opt/compile_gpdb.sh $(pwd)"

	setup_gpadmin_user
	transfer_ownership_for_postgis
	make_cluster
	prep_setup_postgis

	su - root -c "bash /opt/setup_postgis.sh $(pwd)"
	su - gpadmin -c "bash /opt/install_postgis.sh $(pwd)"
}

_main "$@"
