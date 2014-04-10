## jstat2gf.pl

jstatからメトリクスを取得してGrowthForecastに送るクン。自動で複合グラフもいくつか作るので便利。

## 使い方

cronで実行してね

    $ crontab -l
    PATH=/path/to/java/bin:/usr/bin
    * * * * * perl /path/to/jstat2gf.pl --gf-uri=http://gf/ --gf-service=example --gf-section=jvm --gf-name-prefix=app001 --jvm-pid=$(pgrep -of 'process name')

## オプション

### -h, --help

ヘルプの表示

### --gf-uri

GrowthForecastのあるURI

### --gf-service

グラフを登録する service_name

### --gf-section

グラフを登録する section_name

### --gf-name-prefix

グラフを登録する graph_nameの頭に付ける文字列

### --jvm-pid

対象JVMプロセスのpid

## インストール

    $ git clone ..
    $ cd jstat2gf
    $ cpanm --installdeps .

