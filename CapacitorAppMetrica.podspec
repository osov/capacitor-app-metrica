require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  # Имя обязано совпадать с тем, что генерирует Capacitor из имени пакета
  # (capacitor-app-metrica -> CapacitorAppMetrica), иначе pod install не найдёт
  # спецификацию. Заодно снимает затенение типа AppMetrica из SDK.
  s.name = 'CapacitorAppMetrica'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  s.source_files = 'ios/Plugin/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target  = '13.0'
  s.dependency 'Capacitor'
  # Зависим от AppMetricaCore, а не от зонтичного AppMetricaAnalytics: тот
  # прибивает Core к своей точной версии и конфликтует с YandexMobileAds,
  # который тянет AppMetricaCore ~> 6.5.0. Импортируем всё равно только Core.
  s.dependency 'AppMetricaCore', '~> 6.5'
  s.swift_version = '5.9'
end
