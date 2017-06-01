#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function prep_compile_gpdb(){

  cat > /opt/compile_gpdb.sh <<-EOF

		set -exo pipefail
		base_path=\${1}
		source /opt/gcc_env.sh
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
        export CMAKE_HOME=$(pwd)

        sudo yum install -y zip unzip
        wget https://github.com/greenplum-db/gp-xerces/archive/master.zip
        sudo unzip master.zip
        cd gp-xerces-master
        mkdir build
        cd build
        ../configure --prefix=/usr/local
        make
        sudo make install
        export LDFLAGS='-L/usr/local/lib/'
        export LD_LIBRARY_PATH=/usr/local/lib/:$LD_LIBRARY_PATH
        sudo rm master.zip
        cd /tmp/

        sudo touch /etc/ld.so.conf.d/test1.conf
        sudo echo "/usr/local/lib" >> /etc/ld.so.conf.d/test1.conf
        sudo ldconfig

        wget https://github.com/greenplum-db/gporca/archive/master.zip
        sudo unzip master.zip
        cd gporca-master/
        mkdir build
        cd build
        $CMAKE_HOME/cmake ../
        make
        sudo make install
        cd /tmp/

		cd \${base_path}/gpdb_src
		./configure --with-libxml --with-libxslt --with-python --with-perl --prefix=/tmp/gpdb-deploy --disable-orca
		make
		sudo make install
		cd \${base_path}


	EOF

	chmod a+x /opt/compile_gpdb.sh
}


function setup_gpadmin_user() {
	./gpdb_src/concourse/scripts/setup_gpadmin_user.bash "$TEST_OS"
}

function prep_setup_postgis() {
	cat > /opt/setup_postgis.sh <<-EOF
		set -exo pipefail
		base_path=\${1}
		source /tmp/gpdb-deploy/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${base_path}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
		# export MASTER_DATA_DIRECTORY=\${base_path}/gpdb_src/gpAux/gpdemo/datadirs/qddir/demoDataDir-1

		# cd /tmp/
		# wget ftp://195.220.108.108/linux/centos/7.3.1611/os/x86_64/Packages/json-c-devel-0.11-4.el7_0.x86_64.rpm
		# sudo yum install json-c-devel-0.11-4.el7_0.x86_64.rpm
		sudo yum install -y libxml2-devel
		sudo yum install -y geos-devel
		sudo yum install -y proj-devel
		sudo yum install -y gdal-devel
		sudo yum install -y expat-devel
		sudo yum install -y patch
		sudo yum install -y CUnit CUnit-devel
		wget ftp://invisible-island.net/byacc/byacc-20170430.tgz
		tar -xzf byacc-20170430.tgz
		cd byacc-20170430/
		./configure --enable-btyacc
		make
		sudo make install
		# export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH

		cd \${base_path}/postgis_src/postgis/
		make remove
		make prepare
		cd build/postgis-2.1.5/
		./configure --with-pgconfig=$GPHOME/bin/pg_config --with-raster --without-topology --prefix=$GPHOME --libdir=/usr/lib64
		make
		make install

		mv \${base_path}/postgis_src/postgis/build/postgis-2.1.5/regress/loader \${base_path}/postgis_src/postgis/build/postgis-2.1.5/regress/bkp_loader

		chown -R gpadmin:gpadmin \${base_path}/postgis_src
	EOF

	cat > /opt/install_postgis.sh <<-EOF
		set -exo pipefail
		base_path=\${1}
		source /tmp/gpdb-deploy/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${base_path}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
		cd \${base_path}/postgis_src/postgis/build/postgis-2.1.5/

		make check

		gpstate -a

		cd $GPHOME/share/postgresql/contrib/postgis-2.1
		psql template1 -f postgis.sql
		psql template1 -f postgis_comments.sql
		psql template1 -f spatial_ref_sys.sql
		psql template1 -f rtpostgis.sql
		psql template1 -f raster_comments.sql

	EOF

	chmod a+x /opt/setup_postgis.sh
	chmod a+x /opt/install_postgis.sh
}


transfer_ownership_for_postgis() {
  chown -R gpadmin:gpadmin postgis_src
  [ -d /tmp/gpdb-deploy ] && chown -R gpadmin:gpadmin /tmp/gpdb-deploy
}

function make_cluster() {
  source /tmp/gpdb-deploy/greenplum_path.sh
  export BLDWRAP_POSTGRES_CONF_ADDONS=${BLDWRAP_POSTGRES_CONF_ADDONS}
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
